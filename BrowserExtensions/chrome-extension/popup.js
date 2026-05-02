(function () {
  "use strict";

  // ═══ Predefined site registry ═══
  const SITES = [
    { name: "WhatsApp",    host: "web.whatsapp.com",    icon: "https://img.icons8.com/color/48/whatsapp--v2.png"         },
    { name: "Instagram",   host: "www.instagram.com",   icon: "https://img.icons8.com/color/48/instagram-new--v2.png"    },
    { name: "Telegram",    host: "web.telegram.org",    icon: "https://img.icons8.com/color/48/telegram-app--v2.png"     },
    { name: "Messenger",   host: "www.messenger.com",   icon: "https://img.icons8.com/color/48/facebook-messenger--v5.png" },
    { name: "Discord",     host: "discord.com",         icon: "https://img.icons8.com/color/48/discord-logo.png"         },
    { name: "Slack",       host: "app.slack.com",       icon: "https://img.icons8.com/color/48/slack-new.png"            },
    { name: "X / Twitter", host: "x.com",               icon: "https://img.icons8.com/color/48/twitterx.png"            },
    { name: "Facebook",    host: "www.facebook.com",    icon: "https://img.icons8.com/color/48/facebook-new.png"         },
    { name: "LinkedIn",    host: "www.linkedin.com",    icon: "https://img.icons8.com/color/48/linkedin.png"             },
    { name: "Gmail",       host: "mail.google.com",     icon: "https://img.icons8.com/color/48/gmail-new.png"            },
    { name: "Outlook",     host: "outlook.live.com",    icon: "https://img.icons8.com/color/48/ms-outlook.png"           },
    { name: "Teams",       host: "teams.microsoft.com", icon: "https://img.icons8.com/color/48/microsoft-teams.png"      },
    { name: "Element",     host: "app.element.io",      icon: "https://img.icons8.com/color/48/matrix-architect.png"     },
  ];
  const PREDEFINED_HOSTS = new Set(SITES.map(s => s.host));

  const LOCK_ICON_SVG = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#30D158" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>';
  const LOCK_ICON_STYLE = 'background:rgba(48,209,88,0.10);border:1px solid rgba(48,209,88,0.22);';

  // ═══ DOM refs ═══
  const blurStatusCard    = document.getElementById("blurStatusCard");
  const blurStatusLabel   = document.getElementById("blurStatusLabel");
  const blurStatusSub     = document.getElementById("blurStatusSub");
  const blurToggle        = document.getElementById("blurToggle");
  const blurSlider        = document.getElementById("blurSlider");
  const blurValPill       = document.getElementById("blurValPill");
  const blurAvatarsToggle = document.getElementById("blurAvatarsToggle");
  const hideModeToggle    = document.getElementById("hideModeToggle");
  const presetBtns        = document.querySelectorAll(".preset-btn");

  const pwStatus          = document.getElementById("pwStatus");
  const pwStatusText      = document.getElementById("pwStatusText");
  const pwStatusBadge     = document.getElementById("pwStatusBadge");
  const pwChangeArea      = document.getElementById("pwChangeArea");
  const pwChangeForm      = document.getElementById("pwChangeForm");
  const pwChangeBtn       = document.getElementById("pwChangeBtn");
  const pwRemoveBtn       = document.getElementById("pwRemoveBtn");
  const pwCurrentInput    = document.getElementById("pwCurrentInput");
  const pwNewInput1       = document.getElementById("pwNewInput1");
  const pwNewInput2       = document.getElementById("pwNewInput2");
  const pwConfirmChangeBtn= document.getElementById("pwConfirmChangeBtn");
  const pwCancelChangeBtn = document.getElementById("pwCancelChangeBtn");
  const pwChangeMsg       = document.getElementById("pwChangeMsg");
  const lockSitesList     = document.getElementById("lockSitesList");
  const lockCount         = document.getElementById("lockCount");

  const customSiteInput   = document.getElementById("customSiteInput");
  const addCustomSiteBtn  = document.getElementById("addCustomSiteBtn");
  const customSiteError   = document.getElementById("customSiteError");
  const customSitesList   = document.getElementById("customSitesList");
  const customLockCount   = document.getElementById("customLockCount");

  const autoRelockToggle  = document.getElementById("autoRelockToggle");

  // ─── Multi-passkey DOM refs ───
  const passkeyList          = document.getElementById("passkeyList");
  const passkeyEmpty         = document.getElementById("passkeyEmpty");
  const addPasskeyBtn        = document.getElementById("addPasskeyBtn");
  const addPasskeyModal      = document.getElementById("addPasskeyModal");
  const addPasskeyCancelBtn  = document.getElementById("addPasskeyCancelBtn");
  const pkLabelInput         = document.getElementById("pkLabelInput");
  const kindPlatformBtn      = document.getElementById("kindPlatformBtn");
  const kindPlatformDesc     = document.getElementById("kindPlatformDesc");
  const renamePasskeyModal   = document.getElementById("renamePasskeyModal");
  const renamePasskeyInput   = document.getElementById("renamePasskeyInput");
  const renamePasskeySaveBtn = document.getElementById("renamePasskeySaveBtn");
  const renamePasskeyCancelBtn = document.getElementById("renamePasskeyCancelBtn");

  const genRecoveryBtn       = document.getElementById("genRecoveryBtn");
  const recoveryCountBadge   = document.getElementById("recoveryCountBadge");
  const recoveryModal        = document.getElementById("recoveryModal");
  const recoveryCodesGrid    = document.getElementById("recoveryCodesGrid");
  const recoveryCopyBtn      = document.getElementById("recoveryCopyBtn");
  const recoveryDownloadBtn  = document.getElementById("recoveryDownloadBtn");
  const recoveryDoneBtn      = document.getElementById("recoveryDoneBtn");

  const mRecoveryBtn         = document.getElementById("mRecoveryBtn");
  const mRecoveryForm        = document.getElementById("mRecoveryForm");
  const mRecoveryInput       = document.getElementById("mRecoveryInput");
  const mRecoverySubmitBtn   = document.getElementById("mRecoverySubmitBtn");
  const mRecoveryMsg         = document.getElementById("mRecoveryMsg");

  // ═══ Master Lock DOM refs ═══
  const masterOverlay = document.getElementById("masterOverlay");
  const masterSetup   = document.getElementById("masterSetup");
  const masterLogin   = document.getElementById("masterLogin");
  const mSetupPw1     = document.getElementById("mSetupPw1");
  const mSetupPw2     = document.getElementById("mSetupPw2");
  const mSetupBtn     = document.getElementById("mSetupBtn");
  const mSetupMsg     = document.getElementById("mSetupMsg");
  const mLoginPw      = document.getElementById("mLoginPw");
  const mLoginBtn     = document.getElementById("mLoginBtn");
  const mTouchIDBtn   = document.getElementById("mTouchIDBtn");
  const mLoginMsg     = document.getElementById("mLoginMsg");

  // ═══ MASTER LOCK INIT ═══
  function initMasterLock() {
    chrome.runtime.sendMessage({ action: "ms_hasPassword" }, (resp) => {
      if (chrome.runtime.lastError) return;
      if (!resp || !resp.hasPassword) {
        masterOverlay.style.display = "flex";
        masterSetup.style.display = "block";
        masterLogin.style.display = "none";
      } else {
        masterOverlay.style.display = "flex";
        masterSetup.style.display = "none";
        masterLogin.style.display = "block";
        mLoginPw.focus();

        // Show "Sign in with passkey" whenever any passkey exists — not just
        // on macOS. Cross-device + roaming credentials work on every platform.
        chrome.runtime.sendMessage({ action: "ms_listPasskeys" }, (r) => {
          if (r && Array.isArray(r.passkeys) && r.passkeys.length > 0) {
            if (mTouchIDBtn) mTouchIDBtn.style.display = "flex";
          }
        });

        // Show "Use recovery code" link if any unused codes exist.
        chrome.runtime.sendMessage({ action: "ms_hasRecoveryCodes" }, (r) => {
          if (r && r.unused > 0 && mRecoveryBtn) mRecoveryBtn.style.display = "block";
        });
      }
    });
  }
  initMasterLock();

  mSetupBtn.addEventListener("click", () => {
    const p1 = mSetupPw1.value, p2 = mSetupPw2.value;
    mSetupMsg.className = "pw-msg";
    if (!p1) { mSetupMsg.textContent = "Enter a password"; mSetupMsg.className = "pw-msg err"; return; }
    if (p1.length < 4) { mSetupMsg.textContent = "Min 4 characters"; mSetupMsg.className = "pw-msg err"; return; }
    if (p1 !== p2) { mSetupMsg.textContent = "Passwords don't match"; mSetupMsg.className = "pw-msg err"; return; }
    mSetupBtn.disabled = true;
    mSetupBtn.textContent = "Saving...";
    chrome.runtime.sendMessage({ action: "ms_setPassword", password: p1 }, (resp) => {
      mSetupBtn.disabled = false;
      mSetupBtn.textContent = "Set Password";
      if (resp && resp.ok) {
        masterOverlay.style.display = "none";
        document.body.classList.remove("locked");
        if (typeof loadPwState === "function") loadPwState();
      } else {
        mSetupMsg.textContent = "Failed"; mSetupMsg.className = "pw-msg err";
      }
    });
  });

  function attemptMasterLogin() {
    const pw = mLoginPw.value;
    if (!pw) return;
    mLoginBtn.disabled = true;
    mLoginBtn.textContent = "Checking...";
    chrome.runtime.sendMessage({ action: "ms_verifyPassword", password: pw }, (resp) => {
      mLoginBtn.disabled = false;
      mLoginBtn.textContent = "Unlock";
      if (resp && resp.ok) {
        masterOverlay.style.display = "none";
        document.body.classList.remove("locked");
        if (typeof loadPwState === "function") loadPwState();
      } else {
        mLoginMsg.textContent = "Incorrect password"; mLoginMsg.className = "pw-msg err";
        mLoginPw.value = ""; mLoginPw.focus();
      }
    });
  }

  mLoginBtn.addEventListener("click", attemptMasterLogin);
  mLoginPw.addEventListener("keydown", (e) => {
    if (e.key === "Enter") attemptMasterLogin();
    if (mLoginMsg.textContent) mLoginMsg.textContent = "";
  });
  
  [mSetupPw1, mSetupPw2].forEach(el => el.addEventListener("keydown", (e) => {
    if (e.key === "Enter") mSetupBtn.click();
    if (mSetupMsg.textContent) mSetupMsg.textContent = "";
  }));

  // ═══ Touch ID button in master login ═══
  if (mTouchIDBtn) {
    mTouchIDBtn.addEventListener("click", () => {
      mTouchIDBtn.disabled = true;
      mLoginMsg.textContent = "";
      mLoginMsg.className   = "pw-msg";
      chrome.runtime.sendMessage(
        { action: "ms_openTouchID", hostname: "_master", mode: "auth" },
        () => {
          if (chrome.runtime.lastError) {
            mTouchIDBtn.disabled  = false;
            mLoginMsg.textContent = "Touch ID unavailable";
            mLoginMsg.className   = "pw-msg err";
          }
        }
      );
    });
  }

  // Listen for Touch ID success from auth.html popup (ms_masterUnlocked broadcast)
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.action === "ms_masterUnlocked") {
      masterOverlay.style.display = "none";
      document.body.classList.remove("locked");
      if (typeof loadPwState === "function") loadPwState();
    }
  });

  // ═══ Tab switching ═══
  document.querySelectorAll(".tab-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
      document.querySelectorAll(".tab-panel").forEach(p => p.classList.remove("active"));
      btn.classList.add("active");
      document.getElementById("panel-" + btn.dataset.tab).classList.add("active");
      document.querySelector(".popup-scroll").scrollTop = 0;
    });
  });

  // ═══ Helpers ═══
  function sendToTab(msg, cb) {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (!tabs[0]) return;
      chrome.tabs.sendMessage(tabs[0].id, msg, (resp) => {
        if (chrome.runtime.lastError) return;
        if (cb && resp) cb(resp);
      });
    });
  }

  function getTabHostname(tab) {
    try { return new URL(tab.url || "").hostname; } catch { return ""; }
  }

  function updateSliderFill(val) {
    const pct = ((val - 2) / (30 - 2)) * 100;
    blurSlider.style.setProperty("--fill", pct + "%");
  }

  function syncPresets(val) {
    presetBtns.forEach(b => b.classList.toggle("active", parseInt(b.dataset.val) === val));
  }

  function updateBlurUI(active) {
    blurToggle.checked = active;
    blurStatusCard.className = "status-card " + (active ? "on" : "off");
    blurStatusLabel.textContent = active ? "Blur Active" : "Blur Inactive";
    blurStatusSub.textContent   = active ? "Hover over content to reveal" : "Content is fully visible";
  }

  function updateHideUI(hide) {
    blurSlider.classList.toggle("dim", hide);
    blurValPill.classList.toggle("dim", hide);
    presetBtns.forEach(b => b.disabled = hide);
  }

  // ═══ Init blur state (fixed fallback reads per-site key from storage) ═══
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (!tabs[0]) {
      updateBlurUI(false);
      return;
    }

    chrome.tabs.sendMessage(tabs[0].id, { action: "getState" }, (resp) => {
      if (chrome.runtime.lastError || !resp) {
        // Fallback: read from storage using the site-specific key
        const host = getTabHostname(tabs[0]);
        const siteKey = "macshield_" + host.replace(/\./g, "_");

        chrome.storage.local.get([siteKey, "ms_blur_level", "ms_blur_avatars", "ms_hide_mode"], (r) => {
          // Blur only meaningful on protected sites; default to true if site key not yet set
          const onProtectedSite = PREDEFINED_HOSTS.has(host);
          const isActive = onProtectedSite ? (r[siteKey] !== false) : false;
          updateBlurUI(isActive);

          const lv = r["ms_blur_level"] || 12;
          blurSlider.value = lv; blurValPill.textContent = lv + "px";
          updateSliderFill(lv); syncPresets(lv);
          blurAvatarsToggle.checked = r["ms_blur_avatars"] === true;
          hideModeToggle.checked    = r["ms_hide_mode"]   === true;
          updateHideUI(r["ms_hide_mode"] === true);

          if (!onProtectedSite) {
            blurStatusLabel.textContent = "Not a protected site";
            blurStatusSub.textContent   = "Open WhatsApp, Gmail, etc. to use blur";
          }
        });
        return;
      }
      updateBlurUI(resp.active);
      const lv = resp.blurLevel || 12;
      blurSlider.value = lv; blurValPill.textContent = lv + "px";
      updateSliderFill(lv); syncPresets(lv);
      blurAvatarsToggle.checked = resp.blurAvatars || false;
      hideModeToggle.checked    = resp.hideMode    || false;
      updateHideUI(resp.hideMode || false);
    });
  });

  updateSliderFill(parseInt(blurSlider.value));

  // ═══ Blur controls ═══
  blurToggle.addEventListener("change", () => {
    sendToTab({ action: "toggle" }, (r) => updateBlurUI(r.active));
  });
  blurSlider.addEventListener("input", () => {
    const v = parseInt(blurSlider.value);
    blurValPill.textContent = v + "px"; updateSliderFill(v); syncPresets(v);
    sendToTab({ action: "setBlurLevel", level: v });
  });
  presetBtns.forEach(btn => {
    btn.addEventListener("click", () => {
      const v = parseInt(btn.dataset.val);
      blurSlider.value = v; blurValPill.textContent = v + "px";
      updateSliderFill(v); syncPresets(v);
      sendToTab({ action: "setBlurLevel", level: v });
    });
  });
  blurAvatarsToggle.addEventListener("change", () => {
    sendToTab({ action: "setBlurAvatars", enabled: blurAvatarsToggle.checked });
    chrome.storage.local.set({ ms_blur_avatars: blurAvatarsToggle.checked });
  });
  hideModeToggle.addEventListener("change", () => {
    updateHideUI(hideModeToggle.checked);
    sendToTab({ action: "setHideMode", enabled: hideModeToggle.checked });
    chrome.storage.local.set({ ms_hide_mode: hideModeToggle.checked });
  });

  // ═══════════════════════════════════════
  // PASSWORD MANAGEMENT
  // ═══════════════════════════════════════

  let lockedSites = {};

  function loadPwState() {
    chrome.runtime.sendMessage({ action: "ms_hasPassword" }, (resp) => {
      const hasPw = !!(resp && resp.hasPassword);
      if (hasPw) {
        pwStatus.className = "pw-status set";
        pwStatusText.innerHTML = `
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
            <polyline points="20 6 9 17 4 12"/>
          </svg>
          Password set &mdash; locks enabled`;
        pwStatusBadge.innerHTML = `<span style="color:var(--text);font-weight:700;font-size:10px;">Active</span>`;
        pwChangeForm.style.display = "none";
        pwChangeArea.style.display = "flex";
      } else {
        document.body.classList.add("locked");
        initMasterLock();
      }
    });
  }
  loadPwState();

  pwChangeBtn.addEventListener("click", () => {
    pwChangeArea.style.display = "none";
    pwChangeForm.style.display = "block";
    pwCurrentInput.value = ""; pwNewInput1.value = ""; pwNewInput2.value = "";
    pwChangeMsg.textContent = "";
    pwCurrentInput.focus();
  });

  pwCancelChangeBtn.addEventListener("click", () => {
    pwChangeForm.style.display = "none";
    pwChangeArea.style.display = "flex";
  });

  pwConfirmChangeBtn.addEventListener("click", () => {
    const cur = pwCurrentInput.value, n1 = pwNewInput1.value, n2 = pwNewInput2.value;
    pwChangeMsg.className = "pw-msg";
    if (!cur)       { pwChangeMsg.textContent = "Enter current password"; pwChangeMsg.className = "pw-msg err"; return; }
    if (!n1)        { pwChangeMsg.textContent = "Enter new password"; pwChangeMsg.className = "pw-msg err"; return; }
    if (n1.length < 4){ pwChangeMsg.textContent = "Minimum 4 characters"; pwChangeMsg.className = "pw-msg err"; return; }
    if (n1 !== n2)  { pwChangeMsg.textContent = "New passwords don't match"; pwChangeMsg.className = "pw-msg err"; return; }

    pwConfirmChangeBtn.disabled = true;
    pwConfirmChangeBtn.textContent = "Verifying…";

    chrome.runtime.sendMessage({ action: "ms_verifyPassword", password: cur }, (resp) => {
      if (!resp || !resp.ok) {
        pwChangeMsg.textContent = "Current password is incorrect"; pwChangeMsg.className = "pw-msg err";
        pwConfirmChangeBtn.disabled = false; pwConfirmChangeBtn.textContent = "Update Password";
        return;
      }
      chrome.runtime.sendMessage({ action: "ms_setPassword", password: n1 }, (r) => {
        pwConfirmChangeBtn.disabled = false; pwConfirmChangeBtn.textContent = "Update Password";
        if (r && r.ok) {
          pwChangeMsg.textContent = "Password updated"; pwChangeMsg.className = "pw-msg ok";
          setTimeout(() => loadPwState(), 1000);
        } else {
          pwChangeMsg.textContent = "Failed to update"; pwChangeMsg.className = "pw-msg err";
        }
      });
    });
  });

  pwRemoveBtn.addEventListener("click", () => {
    if (pwRemoveBtn.textContent === "Remove") {
      pwRemoveBtn.textContent = "Click to confirm";
      setTimeout(() => { if (pwRemoveBtn.textContent === "Click to confirm") pwRemoveBtn.textContent = "Remove"; }, 3000);
      return;
    }
    pwRemoveBtn.textContent = "Removing…";
    chrome.runtime.sendMessage({ action: "ms_removePassword" }, () => {
      chrome.runtime.sendMessage({ action: "ms_setLockedSites", sites: {} }, () => {
        lockedSites = {};
        renderLockSites(); renderCustomSites();
        loadPwState();
        setTimeout(() => pwRemoveBtn.textContent = "Remove", 100);
      });
    });
  });

  // Enter key support
  [pwCurrentInput, pwNewInput1, pwNewInput2].forEach(el => el.addEventListener("keydown", e => { if (e.key === "Enter") pwConfirmChangeBtn.click(); }));

  // ═══════════════════════════════════════
  // LOCK ANY WEBSITE — CUSTOM SITES
  // ═══════════════════════════════════════

  function parseDomain(raw) {
    try {
      let s = raw.trim().toLowerCase();
      if (!s) return null;
      if (!s.startsWith("http")) s = "https://" + s;
      const host = new URL(s).hostname;
      return host || null;
    } catch { return null; }
  }

  function getCustomSites() {
    const custom = {};
    for (const [h, v] of Object.entries(lockedSites)) {
      if (!PREDEFINED_HOSTS.has(h) && v) custom[h] = true;
    }
    return custom;
  }

  function renderCustomSites() {
    const custom = getCustomSites();
    const keys = Object.keys(custom);
    customLockCount.textContent = keys.length ? keys.length + " locked" : "";
    if (!keys.length) {
      customSitesList.innerHTML = '<div class="no-custom-sites">No custom sites locked yet</div>';
      return;
    }
    customSitesList.innerHTML = keys.map(host => `
      <div class="custom-site-row">
        <div class="site-icon" style="${LOCK_ICON_STYLE}">${LOCK_ICON_SVG}</div>
        <span class="custom-site-name">${host}</span>
        <button class="remove-site-btn" data-host="${host}">Remove</button>
      </div>`).join("");

    customSitesList.querySelectorAll(".remove-site-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        const host = btn.dataset.host;
        delete lockedSites[host];
        chrome.runtime.sendMessage({ action: "ms_setLockedSites", sites: lockedSites }, () => {
          renderCustomSites();
          updateLockCountBadges();
        });
      });
    });
  }

  addCustomSiteBtn.addEventListener("click", addCustomSite);
  customSiteInput.addEventListener("keydown", e => { if (e.key === "Enter") addCustomSite(); });

  function addCustomSite() {
    customSiteError.style.display = "none";
    const domain = parseDomain(customSiteInput.value);

    if (!domain) {
      customSiteError.textContent = "Enter a valid domain (e.g. github.com)";
      customSiteError.style.display = "block";
      return;
    }
    if (lockedSites[domain]) {
      customSiteError.textContent = domain + " is already locked";
      customSiteError.style.display = "block";
      return;
    }

    chrome.runtime.sendMessage({ action: "ms_hasPassword" }, (resp) => {
      if (!resp || !resp.hasPassword) {
        customSiteError.textContent = "Set a password first to enable locks";
        customSiteError.style.display = "block";
        return;
      }
      lockedSites[domain] = true;
      chrome.runtime.sendMessage({ action: "ms_setLockedSites", sites: lockedSites }, () => {
        customSiteInput.value = "";
        renderCustomSites();
        updateLockCountBadges();
      });
    });
  }

  // ═══════════════════════════════════════
  // PREDEFINED LOCK SITES
  // ═══════════════════════════════════════

  function updateLockCountBadges() {
    let predefinedCount = 0;
    for (const s of SITES) { if (lockedSites[s.host]) predefinedCount++; }
    lockCount.textContent = predefinedCount ? predefinedCount + " locked" : "none locked";
  }

  function loadLockSites() {
    chrome.runtime.sendMessage({ action: "ms_getLockedSites" }, (resp) => {
      lockedSites = (resp && resp.sites) || {};
      renderLockSites();
      renderCustomSites();
      updateLockCountBadges();
    });
  }

  function renderLockSites() {
    lockSitesList.innerHTML = SITES.map(site => {
      const isLocked = !!lockedSites[site.host];
      return `
        <div class="lock-site-row">
          <div class="site-icon" style="background:transparent;border:none;overflow:hidden;">
            <img src="${site.icon}" width="28" height="28" style="border-radius:7px;display:block;" alt="${site.name}">
          </div>
          <div class="lock-site-name">
            <strong>${site.name}</strong>
            <small>${site.host}</small>
          </div>
          <label class="sw">
            <input type="checkbox" data-host="${site.host}" class="lock-site-check" ${isLocked ? "checked" : ""}>
            <span class="sw-track"></span>
          </label>
        </div>`;
    }).join("");

    lockSitesList.querySelectorAll(".lock-site-check").forEach(cb => {
      cb.addEventListener("change", () => {
        chrome.runtime.sendMessage({ action: "ms_hasPassword" }, (resp) => {
          if (!resp || !resp.hasPassword) {
            cb.checked = false;
            document.querySelector('[data-tab="lock"]').click();
            pwChangeMsg.textContent = "Set a password first to enable App Lock";
            pwChangeMsg.className = "pw-msg err";
            return;
          }
          if (cb.checked) lockedSites[cb.dataset.host] = true;
          else delete lockedSites[cb.dataset.host];
          chrome.runtime.sendMessage({ action: "ms_setLockedSites", sites: lockedSites }, () => {
            updateLockCountBadges();
          });
        });
      });
    });
  }

  loadLockSites();

  // ═══════════════════════════════════════
  // MULTI-PASSKEY MANAGEMENT
  // ═══════════════════════════════════════

  const KIND_META = {
    "platform": {
      title: "Platform",
      sub:   (os) => os === "mac" ? "Touch ID on this Mac"
                  : os === "win" ? "Windows Hello on this PC"
                  : os === "android" ? "Biometric on this device"
                  : "This device",
      svg: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4"/><path d="M14 13.12c0 2.38 0 6.38-1 8.88"/><path d="M17.29 21.02c.12-.6.43-2.3-.5-3.02"/><path d="M2 12a10 10 0 0 1 18-6"/><path d="M2 16h.01"/><path d="M21.8 16c.2-2 .131-5.354 0-6"/><path d="M5 19.5C5.5 18 6 15 6 12a6 6 0 0 1 .34-2"/><path d="M8.65 22c.21-.66.45-1.32.57-2"/><path d="M9 6.8a6 6 0 0 1 9 5.2v2"/></svg>',
    },
    "cross-device": {
      title: "Phone or tablet",
      sub:   () => "Cross-device (QR / hybrid)",
      svg: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="2" width="10" height="20" rx="2"/><line x1="11" y1="18" x2="13" y2="18"/></svg>',
    },
    "roaming": {
      title: "Security key",
      sub:   () => "USB / NFC / Bluetooth key",
      svg: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="9" width="20" height="6" rx="2"/><circle cx="6" cy="12" r="0.6" fill="currentColor"/><circle cx="10" cy="12" r="0.6" fill="currentColor"/></svg>',
    },
  };

  let currentPasskeys = [];
  let pendingAddPoll = null;
  let platformOS = "";

  function formatRelative(ts) {
    if (!ts) return "Never used";
    const diff = Date.now() - ts;
    const m = Math.floor(diff / 60000);
    if (m < 1) return "Just now";
    if (m < 60) return m + "m ago";
    const h = Math.floor(m / 60);
    if (h < 24) return h + "h ago";
    const d = Math.floor(h / 24);
    if (d < 30) return d + "d ago";
    return new Date(ts).toLocaleDateString();
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    })[c]);
  }

  function renderPasskeys(list) {
    // Clear any menu popups that were reparented to <body> on a previous
    // render — otherwise they'd accumulate as orphans.
    document.querySelectorAll("body > .pk-menu-pop").forEach((el) => el.remove());

    currentPasskeys = list || [];
    if (currentPasskeys.length === 0) {
      passkeyList.innerHTML = '<div class="pk-empty">No passkeys yet. Add one to unlock with biometrics, a phone, or a security key.</div>';
      return;
    }
    passkeyList.innerHTML = currentPasskeys.map((p, i) => {
      const meta = KIND_META[p.kind] || KIND_META.platform;
      const subParts = [ meta.sub(platformOS) ];
      subParts.push(formatRelative(p.lastUsedAt));
      return `
        <div class="pk-row" data-idx="${i}">
          <div class="pk-icon">${meta.svg}</div>
          <div class="pk-info">
            <div class="pk-label">${escapeHtml(p.label || meta.title)}</div>
            <div class="pk-sub">${subParts.map(escapeHtml).join(" · ")}</div>
          </div>
          <div class="pk-menu">
            <button class="pk-menu-btn" data-menu-idx="${i}" aria-label="Menu">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                <circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/>
              </svg>
            </button>
            <div class="pk-menu-pop" id="pk-pop-${i}">
              <button class="pk-menu-item"        data-action="rename" data-idx="${i}">Rename</button>
              <button class="pk-menu-item danger" data-action="remove" data-idx="${i}">Remove</button>
            </div>
          </div>
        </div>`;
    }).join("");

    // Wire menu buttons.
    // Popups are moved to <body> on open so they escape the section's
    // overflow:hidden clip, and positioned via the button's bounding rect.
    passkeyList.querySelectorAll(".pk-menu-btn").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        const idx = btn.dataset.menuIdx;
        const wasOpen = document.getElementById("pk-pop-" + idx)
          ?.classList.contains("open");
        closeAllMenus();
        if (wasOpen) return; // toggle off
        const pop = document.getElementById("pk-pop-" + idx);
        if (!pop) return;
        // Reparent to body so position:fixed coordinates are viewport-based
        // and nothing clips it.
        if (pop.parentElement !== document.body) document.body.appendChild(pop);
        const r = btn.getBoundingClientRect();
        const popWidth = 140; // matches min-width + padding
        pop.style.top  = (r.bottom + 4) + "px";
        pop.style.left = Math.max(8, Math.min(
          window.innerWidth - popWidth - 8,
          r.right - popWidth
        )) + "px";
        pop.classList.add("open");
      });
    });
    passkeyList.querySelectorAll(".pk-menu-item").forEach((item) => {
      item.addEventListener("click", (e) => {
        e.stopPropagation();
        const idx = parseInt(item.dataset.idx, 10);
        const action = item.dataset.action;
        closeAllMenus();
        const p = currentPasskeys[idx];
        if (!p) return;
        if (action === "rename") openRenameModal(p);
        else if (action === "remove") confirmRemovePasskey(p);
      });
    });
  }

  function closeAllMenus() {
    document.querySelectorAll(".pk-menu-pop.open").forEach((el) => el.classList.remove("open"));
  }
  document.addEventListener("click", closeAllMenus);

  function loadPasskeys() {
    chrome.runtime.sendMessage({ action: "ms_listPasskeys" }, (r) => {
      renderPasskeys((r && r.passkeys) || []);
    });
  }

  // Detect platform + gate the "This device" modal row
  chrome.runtime.getPlatformInfo((info) => {
    platformOS = info.os || "";
    const supported = window.PublicKeyCredential &&
      PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable;
    const check = supported
      ? PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
      : Promise.resolve(false);
    check.then((avail) => {
      if (!avail) {
        kindPlatformBtn.disabled = true;
        if (kindPlatformDesc) kindPlatformDesc.textContent = "Not available on this device";
      } else if (kindPlatformDesc) {
        kindPlatformDesc.textContent =
          platformOS === "mac" ? "Touch ID on this Mac"
          : platformOS === "win" ? "Windows Hello on this PC"
          : "Built-in biometric on this device";
      }
      loadPasskeys();
    });
  });

  // ─── Add-passkey modal ───
  function openAddModal() {
    pkLabelInput.value = "";
    addPasskeyModal.classList.add("open");
  }
  function closeAddModal() { addPasskeyModal.classList.remove("open"); }

  addPasskeyBtn.addEventListener("click", openAddModal);
  addPasskeyCancelBtn.addEventListener("click", closeAddModal);
  addPasskeyModal.addEventListener("click", (e) => {
    if (e.target === addPasskeyModal) closeAddModal();
  });

  document.querySelectorAll(".pk-kind-row").forEach((row) => {
    row.addEventListener("click", () => {
      const kind = row.dataset.kind;
      const label = (pkLabelInput.value || "").trim();
      closeAddModal();
      startEnrollment(kind, label);
    });
  });

  function startEnrollment(kind, label) {
    // Opens auth.html in a tab (same pattern as the original enroll flow).
    chrome.runtime.sendMessage({
      action:   "ms_openTouchID",
      hostname: "_setup",
      mode:     "enroll",
      kind,
      label,
    }, () => {
      // Poll for registry changes so the list refreshes after success.
      if (pendingAddPoll) clearInterval(pendingAddPoll);
      const startCount = currentPasskeys.length;
      let attempts = 0;
      pendingAddPoll = setInterval(() => {
        attempts++;
        chrome.runtime.sendMessage({ action: "ms_listPasskeys" }, (r) => {
          const list = (r && r.passkeys) || [];
          if (list.length !== startCount || attempts > 60) {
            clearInterval(pendingAddPoll); pendingAddPoll = null;
            renderPasskeys(list);
          }
        });
      }, 1000);
    });
  }

  // ─── Rename modal ───
  let renameTarget = null;
  function openRenameModal(passkey) {
    renameTarget = passkey;
    renamePasskeyInput.value = passkey.label || "";
    renamePasskeyModal.classList.add("open");
    setTimeout(() => renamePasskeyInput.focus(), 40);
  }
  function closeRenameModal() {
    renameTarget = null;
    renamePasskeyModal.classList.remove("open");
  }
  renamePasskeyCancelBtn.addEventListener("click", closeRenameModal);
  renamePasskeyModal.addEventListener("click", (e) => {
    if (e.target === renamePasskeyModal) closeRenameModal();
  });
  renamePasskeyInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") renamePasskeySaveBtn.click();
    if (e.key === "Escape") closeRenameModal();
  });
  renamePasskeySaveBtn.addEventListener("click", () => {
    if (!renameTarget) return;
    const label = (renamePasskeyInput.value || "").trim();
    if (!label) return;
    chrome.runtime.sendMessage({
      action: "ms_renamePasskey",
      id:     renameTarget.id,
      label,
    }, () => {
      closeRenameModal();
      loadPasskeys();
    });
  });

  // ─── Remove passkey (two-click confirm inline) ───
  function confirmRemovePasskey(passkey) {
    const label = passkey.label || "this passkey";
    // If this is the last passkey, warn loudly — password becomes the only
    // way back in (plus recovery codes).
    if (currentPasskeys.length === 1) {
      if (!confirm("Remove \"" + label + "\"?\n\nThis is your LAST passkey. You'll need your master password (or a recovery code) to sign in again.")) return;
    } else {
      if (!confirm("Remove \"" + label + "\"?")) return;
    }
    chrome.runtime.sendMessage({ action: "ms_removePasskey", id: passkey.id }, () => {
      loadPasskeys();
    });
  }

  // ═══════════════════════════════════════
  // RECOVERY CODES
  // ═══════════════════════════════════════

  function refreshRecoveryBadge() {
    chrome.runtime.sendMessage({ action: "ms_hasRecoveryCodes" }, (r) => {
      if (!r) return;
      if (r.unused > 0) {
        recoveryCountBadge.textContent = r.unused + " / " + r.total + " unused";
        genRecoveryBtn.textContent = "Regenerate";
      } else if (r.total > 0) {
        recoveryCountBadge.textContent = "All used";
        genRecoveryBtn.textContent = "Generate";
      } else {
        recoveryCountBadge.textContent = "";
        genRecoveryBtn.textContent = "Generate";
      }
    });
  }
  refreshRecoveryBadge();

  genRecoveryBtn.addEventListener("click", () => {
    if (genRecoveryBtn.dataset.armed !== "1") {
      const prev = genRecoveryBtn.textContent;
      genRecoveryBtn.textContent = "Confirm";
      genRecoveryBtn.dataset.armed = "1";
      setTimeout(() => {
        if (genRecoveryBtn.dataset.armed === "1") {
          genRecoveryBtn.textContent = prev;
          genRecoveryBtn.dataset.armed = "";
        }
      }, 3000);
      return;
    }
    genRecoveryBtn.dataset.armed = "";
    genRecoveryBtn.disabled = true;
    genRecoveryBtn.textContent = "Generating…";
    chrome.runtime.sendMessage({ action: "ms_generateRecoveryCodes" }, (r) => {
      genRecoveryBtn.disabled = false;
      if (r && r.ok && Array.isArray(r.codes)) {
        showRecoveryCodes(r.codes);
      } else {
        alert("Failed to generate recovery codes");
      }
      refreshRecoveryBadge();
    });
  });

  function showRecoveryCodes(codes) {
    recoveryCodesGrid.innerHTML = codes
      .map((c) => `<div class="recovery-code">${escapeHtml(c)}</div>`)
      .join("");
    recoveryModal.classList.add("open");

    recoveryCopyBtn.textContent = "Copy all";
    recoveryCopyBtn.onclick = () => {
      navigator.clipboard.writeText(codes.join("\n")).then(() => {
        recoveryCopyBtn.textContent = "Copied ✓";
        setTimeout(() => { recoveryCopyBtn.textContent = "Copy all"; }, 1500);
      });
    };

    recoveryDownloadBtn.onclick = () => {
      const blob = new Blob(
        ["MacShield recovery codes\nGenerated: " + new Date().toISOString() + "\n\n" + codes.join("\n") + "\n"],
        { type: "text/plain" }
      );
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "macshield-recovery-codes.txt";
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    };

    recoveryDoneBtn.onclick = () => recoveryModal.classList.remove("open");
  }

  // ─── Recovery code on master-login overlay ───
  if (mRecoveryBtn) {
    mRecoveryBtn.addEventListener("click", () => {
      mRecoveryForm.style.display = "block";
      mRecoveryBtn.style.display  = "none";
      setTimeout(() => mRecoveryInput.focus(), 40);
    });
  }
  function submitRecovery() {
    const code = (mRecoveryInput.value || "").trim();
    if (!code) return;
    mRecoveryMsg.className = "pw-msg";
    mRecoverySubmitBtn.disabled = true;
    mRecoverySubmitBtn.textContent = "Checking…";
    chrome.runtime.sendMessage({ action: "ms_consumeRecoveryCode", code }, (r) => {
      mRecoverySubmitBtn.disabled = false;
      mRecoverySubmitBtn.textContent = "Recover";
      if (r && r.ok) {
        mRecoveryMsg.textContent = "Recovered — all passkeys have been revoked. Unlocking…";
        mRecoveryMsg.className   = "pw-msg ok";
        setTimeout(() => {
          masterOverlay.style.display = "none";
          document.body.classList.remove("locked");
          if (typeof loadPwState === "function") loadPwState();
          loadPasskeys();
          refreshRecoveryBadge();
        }, 800);
      } else {
        mRecoveryMsg.textContent = "Invalid code";
        mRecoveryMsg.className   = "pw-msg err";
        mRecoveryInput.value = "";
        mRecoveryInput.focus();
      }
    });
  }
  if (mRecoverySubmitBtn) mRecoverySubmitBtn.addEventListener("click", submitRecovery);
  if (mRecoveryInput) {
    mRecoveryInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") submitRecovery();
      if (mRecoveryMsg.textContent) mRecoveryMsg.textContent = "";
    });
  }

  // ═══ Auto-relock ═══
  chrome.storage.local.get(["ms_auto_relock"], (r) => {
    autoRelockToggle.checked = r.ms_auto_relock === true;
  });
  autoRelockToggle.addEventListener("change", () => {
    chrome.storage.local.set({ ms_auto_relock: autoRelockToggle.checked });
  });

})();
