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
      const unlockedSites = await getUnlockedSites();
      const sites = result.ms_locked_sites || {};
      const host = msg.hostname || "";
      const platformInfo = await new Promise(resolve => chrome.runtime.getPlatformInfo(resolve));
      sendResponse({
        isLocked:    !!sites[host],
        isUnlocked:  unlockedSites.has(host),
        hasPassword: !!result.ms_password_hash,
        os:          platformInfo.os,
      });
    })();
    return true; // async
  }

  // -- Touch ID auth / enroll window --
  if (msg.action === "ms_openTouchID") {
    const mode = msg.mode || "auth";
    const authUrl = chrome.runtime.getURL("auth.html") +
      "?host=" + encodeURIComponent(msg.hostname || "") +
      "&mode=" + mode +
      "&tabId=" + (sender.tab ? sender.tab.id : "");
    chrome.windows.create({
      url: authUrl,
      type: "popup",
      width: 420,
      height: 360,
      focused: true,
    });
    sendResponse({ ok: true });
    return false;
  }

  // -- Touch ID success callback (from auth.html) --
  if (msg.action === "ms_touchIDSuccess") {
    if (msg.hostname) {
      addUnlockedSite(msg.hostname).then(() => {
        broadcastLockState(msg.hostname, "ms_unlocked");
      });
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
    chrome.action.setBadgeText({ text: "🔒", tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: "#222222", tabId: tab.id });
  } else {
    chrome.action.setBadgeText({ text: "", tabId: tab.id });
  }
}

console.log("MacShield v3.1 — Background service worker running");
