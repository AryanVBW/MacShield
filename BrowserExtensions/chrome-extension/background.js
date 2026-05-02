/**
 * MacShield — Background Service Worker v3.1
 *
 * Manages:
 *   - Unlocked-session tracking (per-hostname, clears on browser restart, survives SW sleep)
 *   - Password hash verification relay
 *   - Touch ID (WebAuthn) authentication coordination
 *   - Tab cleanup
 */

"use strict";

// ─── Passkey registry (multi-credential) ───
//
// Storage schema:
//   ms_passkeys        : Array<{id,label,kind,transports,createdAt,lastUsedAt,lastUsedHost}>
//   ms_passkey_events  : Array<{t,type,credId?,label?,host?}>   (capped at 50, newest first)
//   ms_recovery_codes  : Array<{hash,salt,used,createdAt}>
//   ms_webauthn_cred_id: legacy single-cred key (kept as mirror for one release)
//
// `kind` ∈ "platform" | "cross-device" | "roaming".
//
const MS_PASSKEYS_KEY     = "ms_passkeys";
const MS_LEGACY_CRED_KEY  = "ms_webauthn_cred_id";
const MS_EVENTS_KEY       = "ms_passkey_events";
const MS_RECOVERY_KEY     = "ms_recovery_codes";
const MAX_EVENTS          = 50;

async function getPasskeys() {
  const r = await chrome.storage.local.get([MS_PASSKEYS_KEY, MS_LEGACY_CRED_KEY]);
  let list = Array.isArray(r[MS_PASSKEYS_KEY]) ? r[MS_PASSKEYS_KEY] : [];

  // One-time migration from v3.1 single-credential schema.
  if (list.length === 0 && r[MS_LEGACY_CRED_KEY]) {
    list = [{
      id:           r[MS_LEGACY_CRED_KEY],
      label:        "This device",
      kind:         "platform",
      transports:   ["internal"],
      createdAt:    Date.now(),
      lastUsedAt:   null,
      lastUsedHost: null,
    }];
    await chrome.storage.local.set({ [MS_PASSKEYS_KEY]: list });
    await logPasskeyEvent({ type: "migrated", credId: list[0].id, label: list[0].label });
  }
  return list;
}

async function setPasskeys(list) {
  await chrome.storage.local.set({ [MS_PASSKEYS_KEY]: list });
  // Mirror into the legacy key for backward-compat readers (auth.js fallback,
  // popup.js Touch ID gating). Prefer a platform credential if available.
  const plat = list.find((p) => p.kind === "platform");
  if (plat) {
    await chrome.storage.local.set({ [MS_LEGACY_CRED_KEY]: plat.id });
  } else {
    await chrome.storage.local.remove(MS_LEGACY_CRED_KEY);
  }
}

async function logPasskeyEvent(ev) {
  const r = await chrome.storage.local.get(MS_EVENTS_KEY);
  const events = Array.isArray(r[MS_EVENTS_KEY]) ? r[MS_EVENTS_KEY] : [];
  events.unshift(Object.assign({ t: Date.now() }, ev));
  if (events.length > MAX_EVENTS) events.length = MAX_EVENTS;
  await chrome.storage.local.set({ [MS_EVENTS_KEY]: events });
}

// ─── Recovery codes ───
// Format: 3 groups of 4 lowercase-hex chars, e.g. "a3f1-92bc-7e04".
// Stored as salted sha-256 hashes (single-use).
function genRecoveryCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex.slice(0, 4) + "-" + hex.slice(4, 8) + "-" + hex.slice(8, 12);
}

function defaultLabel(kind) {
  if (kind === "cross-device") return "Phone or tablet";
  if (kind === "roaming")      return "Security key";
  return "This device";
}
function defaultTransports(kind) {
  if (kind === "cross-device") return ["hybrid", "internal"];
  if (kind === "roaming")      return ["usb", "nfc", "ble"];
  return ["internal"];
}

async function hashRecovery(code, salt) {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(code.replace(/-/g, "").toLowerCase() + salt)
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ─── Session store helper ───
async function getUnlockedSites() {
  const data = await chrome.storage.session.get("unlockedSites");
  return new Set(data.unlockedSites || []);
}
async function addUnlockedSite(host) {
  const sites = await getUnlockedSites();
  sites.add(host);
  await chrome.storage.session.set({ unlockedSites: Array.from(sites) });
}
async function removeUnlockedSite(host) {
  const sites = await getUnlockedSites();
  sites.delete(host);
  await chrome.storage.session.set({ unlockedSites: Array.from(sites) });
}

// ─── Helpers ───

async function sha256(str) {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(str)
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function getHostname(url) {
  try { return new URL(url).hostname; } catch { return ""; }
}

function broadcastLockState(host, actionName) {
  chrome.tabs.query({}, (tabs) => {
    for (const tab of tabs) {
      if (getHostname(tab.url || "") === host) {
        chrome.tabs.sendMessage(tab.id, { action: actionName }).catch(() => {});
      }
    }
  });
}

// ─── Message handler ───

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  // -- Check if a site is currently unlocked this session --
  if (msg.action === "ms_isUnlocked") {
    getUnlockedSites().then(sites => sendResponse({ unlocked: sites.has(msg.hostname || "") }));
    return true; // async
  }

  // -- Mark a site as unlocked for this session --
  if (msg.action === "ms_unlock") {
    const host = msg.hostname || "";
    addUnlockedSite(host).then(() => {
      broadcastLockState(host, "ms_unlocked");
      sendResponse({ ok: true });
    });
    return true; // async
  }

  // -- Re-lock a site (remove from session) --
  if (msg.action === "ms_relock") {
    const host = msg.hostname || "";
    removeUnlockedSite(host).then(() => {
      broadcastLockState(host, "ms_relocked");
      sendResponse({ ok: true });
    });
    return true; // async
  }

  // -- Verify a password against stored hash --
  if (msg.action === "ms_verifyPassword") {
    (async () => {
      try {
        const result = await chrome.storage.local.get(["ms_password_hash", "ms_password_salt"]);
        if (!result.ms_password_hash) {
          sendResponse({ ok: false, error: "no_password" });
          return;
        }
        const hash = await sha256(msg.password + result.ms_password_salt);
        if (hash === result.ms_password_hash) {
          if (msg.hostname) await addUnlockedSite(msg.hostname);
          sendResponse({ ok: true });
        } else {
          sendResponse({ ok: false, error: "wrong_password" });
        }
      } catch (e) {
        sendResponse({ ok: false, error: e.message });
      }
    })();
    return true; // async
  }

  // -- Set / change password --
  if (msg.action === "ms_setPassword") {
    (async () => {
      try {
        const salt = crypto.getRandomValues(new Uint8Array(16))
          .reduce((s, b) => s + b.toString(16).padStart(2, "0"), "");
        const hash = await sha256(msg.password + salt);
        await chrome.storage.local.set({
          ms_password_hash: hash,
          ms_password_salt: salt,
        });
        sendResponse({ ok: true });
      } catch (e) {
        sendResponse({ ok: false, error: e.message });
      }
    })();
    return true;
  }

  // -- Remove password --
  if (msg.action === "ms_removePassword") {
    chrome.storage.local.remove(["ms_password_hash", "ms_password_salt"], () => {
      sendResponse({ ok: true });
    });
    return true;
  }

  // -- Get all locked sites config --
  if (msg.action === "ms_getLockedSites") {
    chrome.storage.local.get(["ms_locked_sites"], (result) => {
      sendResponse({ sites: result.ms_locked_sites || {} });
    });
    return true;
  }

  // -- Set locked sites config --
  if (msg.action === "ms_setLockedSites") {
    chrome.storage.local.set({ ms_locked_sites: msg.sites }, () => {
      sendResponse({ ok: true });
    });
    return true;
  }

  // -- Check if password is set --
  if (msg.action === "ms_hasPassword") {
    (async () => {
      const result = await chrome.storage.local.get(["ms_password_hash"]);
      const platformInfo = await new Promise(resolve => chrome.runtime.getPlatformInfo(resolve));
      sendResponse({ 
        hasPassword: !!result.ms_password_hash,
        os: platformInfo.os
      });
    })();
    return true;
  }

  // -- Get full lock state for a hostname --
  if (msg.action === "ms_getLockState") {
    (async () => {
      const result = await chrome.storage.local.get(["ms_locked_sites", "ms_password_hash"]);
      const passkeys = await getPasskeys();
      const unlockedSites = await getUnlockedSites();
      const sites = result.ms_locked_sites || {};
      const host = msg.hostname || "";
      const platformInfo = await new Promise(resolve => chrome.runtime.getPlatformInfo(resolve));
      sendResponse({
        isLocked:     !!sites[host],
        isUnlocked:   unlockedSites.has(host),
        hasPassword:  !!result.ms_password_hash,
        hasTouchID:   passkeys.length > 0,   // legacy alias
        passkeyCount: passkeys.length,
        os:           platformInfo.os,
      });
    })();
    return true; // async
  }

  // ═══ Multi-passkey registry ═══

  if (msg.action === "ms_listPasskeys") {
    getPasskeys().then((list) => sendResponse({ passkeys: list }));
    return true;
  }

  // Called by auth.js immediately after a successful navigator.credentials.create()
  if (msg.action === "ms_addPasskey") {
    (async () => {
      try {
        const list = await getPasskeys();
        if (list.some((p) => p.id === msg.credId)) {
          sendResponse({ ok: false, error: "duplicate" });
          return;
        }
        const entry = {
          id:           msg.credId,
          label:        (msg.label || "").trim() || defaultLabel(msg.kind),
          kind:         msg.kind || "platform",
          transports:   Array.isArray(msg.transports) && msg.transports.length
                          ? msg.transports
                          : defaultTransports(msg.kind),
          createdAt:    Date.now(),
          lastUsedAt:   null,
          lastUsedHost: null,
        };
        list.push(entry);
        await setPasskeys(list);
        await logPasskeyEvent({ type: "added", credId: entry.id, label: entry.label });
        sendResponse({ ok: true, passkey: entry });
      } catch (e) {
        sendResponse({ ok: false, error: e.message });
      }
    })();
    return true;
  }

  if (msg.action === "ms_renamePasskey") {
    (async () => {
      const list = await getPasskeys();
      const p = list.find((x) => x.id === msg.id);
      if (!p) { sendResponse({ ok: false, error: "not_found" }); return; }
      p.label = (msg.label || "").trim() || p.label;
      await setPasskeys(list);
      sendResponse({ ok: true });
    })();
    return true;
  }

  if (msg.action === "ms_removePasskey") {
    (async () => {
      const list = await getPasskeys();
      const idx = list.findIndex((x) => x.id === msg.id);
      if (idx === -1) { sendResponse({ ok: false, error: "not_found" }); return; }
      const [removed] = list.splice(idx, 1);
      await setPasskeys(list);
      await logPasskeyEvent({ type: "removed", credId: removed.id, label: removed.label });
      sendResponse({ ok: true });
    })();
    return true;
  }

  if (msg.action === "ms_listPasskeyEvents") {
    chrome.storage.local.get(MS_EVENTS_KEY, (r) => {
      sendResponse({ events: r[MS_EVENTS_KEY] || [] });
    });
    return true;
  }

  if (msg.action === "ms_generateRecoveryCodes") {
    (async () => {
      try {
        const codes = [];
        const stored = [];
        for (let i = 0; i < 8; i++) {
          const code = genRecoveryCode();
          const salt = crypto.getRandomValues(new Uint8Array(8))
            .reduce((s, b) => s + b.toString(16).padStart(2, "0"), "");
          const hash = await hashRecovery(code, salt);
          codes.push(code);
          stored.push({ hash, salt, used: false, createdAt: Date.now() });
        }
        await chrome.storage.local.set({ [MS_RECOVERY_KEY]: stored });
        await logPasskeyEvent({ type: "recovery_generated" });
        sendResponse({ ok: true, codes });
      } catch (e) {
        sendResponse({ ok: false, error: e.message });
      }
    })();
    return true;
  }

  if (msg.action === "ms_hasRecoveryCodes") {
    chrome.storage.local.get(MS_RECOVERY_KEY, (r) => {
      const codes = r[MS_RECOVERY_KEY] || [];
      sendResponse({
        total:    codes.length,
        unused:   codes.filter((c) => !c.used).length,
      });
    });
    return true;
  }

  // Verify a recovery code. On success: revoke ALL passkeys (lockout-recovery
  // path from the design doc) and optionally mark a hostname unlocked.
  if (msg.action === "ms_consumeRecoveryCode") {
    (async () => {
      try {
        const raw = String(msg.code || "").trim().toLowerCase();
        if (!raw) { sendResponse({ ok: false, error: "empty" }); return; }
        const r = await chrome.storage.local.get(MS_RECOVERY_KEY);
        const codes = r[MS_RECOVERY_KEY] || [];
        for (const entry of codes) {
          if (entry.used) continue;
          const h = await hashRecovery(raw, entry.salt);
          if (h === entry.hash) {
            entry.used = true;
            await chrome.storage.local.set({ [MS_RECOVERY_KEY]: codes });
            // Revoke every passkey — forces a fresh enrolment.
            await setPasskeys([]);
            await logPasskeyEvent({ type: "recovery_used" });
            if (msg.hostname) await addUnlockedSite(msg.hostname);
            sendResponse({ ok: true });
            return;
          }
        }
        await logPasskeyEvent({ type: "recovery_failed" });
        sendResponse({ ok: false, error: "invalid" });
      } catch (e) {
        sendResponse({ ok: false, error: e.message });
      }
    })();
    return true;
  }

  // -- Passthrough for popup master-unlock broadcast (auth.html -> popup.js) --
  if (msg.action === "ms_masterUnlocked") {
    sendResponse({ ok: true });
    return false;
  }

  // -- Touch ID enroll / master-popup unlock --
  // Content-script page-lock now uses an inline iframe (lock-guard.js) so this
  // path is only hit for enrollment and popup-master-unlock. Those flows open
  // as a browser TAB (integrated inside the browser) rather than a detached
  // popup window, per user UX feedback.
  if (msg.action === "ms_openTouchID") {
    const mode = msg.mode || "auth";
    const kind = msg.kind || "platform";   // platform | cross-device | roaming
    const label = msg.label || "";
    const authUrl = chrome.runtime.getURL("auth.html") +
      "?host="  + encodeURIComponent(msg.hostname || "") +
      "&mode="  + mode +
      "&kind="  + encodeURIComponent(kind) +
      "&label=" + encodeURIComponent(label) +
      "&tabId=" + (sender.tab ? sender.tab.id : "");

    // Reuse an existing MacShield auth tab if one is already open \u2014 prevents
    // duplicate tabs when the user clicks Enroll twice in quick succession.
    chrome.tabs.query({ url: chrome.runtime.getURL("auth.html") + "*" }, (tabs) => {
      if (tabs && tabs.length > 0) {
        chrome.tabs.update(tabs[0].id, { url: authUrl, active: true });
        if (tabs[0].windowId) {
          chrome.windows.update(tabs[0].windowId, { focused: true });
        }
      } else {
        chrome.tabs.create({ url: authUrl, active: true });
      }
    });

    sendResponse({ ok: true });
    return false;
  }

  // -- Touch ID success callback (from auth.html) --
  // 1) mark the host unlocked + broadcast to content scripts
  // 2) switch focus back to the tab that originally requested auth
  // 3) close the auth tab (this one)
  if (msg.action === "ms_touchIDSuccess") {
    const authTabId     = sender.tab ? sender.tab.id : null;
    const originalTabId = (typeof msg.originalTabId === "number") ? msg.originalTabId : null;

    // Stamp lastUsed on the specific credential that just verified.
    if (msg.credId) {
      (async () => {
        const list = await getPasskeys();
        const p = list.find((x) => x.id === msg.credId);
        if (p) {
          p.lastUsedAt   = Date.now();
          p.lastUsedHost = msg.hostname || null;
          await setPasskeys(list);
          await logPasskeyEvent({
            type:   "used",
            credId: p.id,
            label:  p.label,
            host:   msg.hostname || null,
          });
        }
      })();
    }

    const finalize = () => {
      const cleanup = () => {
        if (authTabId != null) {
          chrome.tabs.remove(authTabId).catch(() => {});
        }
      };

      if (originalTabId != null) {
        // Focus original tab + its window, then close the auth tab.
        chrome.tabs.get(originalTabId, (tab) => {
          if (chrome.runtime.lastError || !tab) {
            // Original tab is gone — just close auth tab and let Chrome pick.
            cleanup();
            return;
          }
          chrome.tabs.update(originalTabId, { active: true }, () => {
            void chrome.runtime.lastError;
            if (tab.windowId != null) {
              chrome.windows.update(tab.windowId, { focused: true }, () => {
                void chrome.runtime.lastError;
                cleanup();
              });
            } else {
              cleanup();
            }
          });
        });
      } else {
        cleanup();
      }
    };

    if (msg.hostname) {
      addUnlockedSite(msg.hostname).then(() => {
        broadcastLockState(msg.hostname, "ms_unlocked");
        // Small delay so the content script has time to receive ms_unlocked
        // and start its dismiss animation before we yank the focus back.
        setTimeout(finalize, 120);
      });
    } else {
      finalize();
    }

    sendResponse({ ok: true });
    return false;
  }

  // -- Unlock chrome://extensions --
  if (msg.action === "ms_unlockUninstall") {
    uninstallUnlocked = true;
    setTimeout(() => { uninstallUnlocked = false; }, 300000); // 5 mins
    if (msg.targetUrl && sender.tab) {
      chrome.tabs.update(sender.tab.id, { url: msg.targetUrl }).catch(() => {});
    } else if (msg.targetUrl) {
      chrome.tabs.create({ url: msg.targetUrl });
    }
    sendResponse({ ok: true });
    return false;
  }

  return false;
});

// ─── Badge update: show lock icon when on locked site ───
chrome.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await chrome.tabs.get(activeInfo.tabId);
    updateBadge(tab);
  } catch {}
});

// ─── Uninstall Protection ───
let uninstallUnlocked = false;

chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  const url = change.url || tab.url || tab.pendingUrl;
  if (!url) return;
  if (url.startsWith("chrome://extensions") || url.startsWith("chrome://settings")) {
    if (!uninstallUnlocked) {
      chrome.tabs.update(tabId, { url: chrome.runtime.getURL("uninstall.html?rt=" + encodeURIComponent(url)) }).catch(()=>{});
    }
  }

  if (change.status === "complete") updateBadge(tab);
});

async function updateBadge(tab) {
  if (!tab || !tab.url) return;
  const host = getHostname(tab.url);
  const result = await chrome.storage.local.get(["ms_locked_sites"]);
  const sites = result.ms_locked_sites || {};
  const unlockedSites = await getUnlockedSites();
  if (sites[host] && !unlockedSites.has(host)) {
    chrome.action.setBadgeText({ text: "ON", tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: "#FF3B30", tabId: tab.id });
  } else {
    chrome.action.setBadgeText({ text: "", tabId: tab.id });
  }
}

console.log("MacShield v3.1 — Background service worker running");
