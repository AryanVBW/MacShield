(function () {
  "use strict";

  // ═══ Predefined site registry ═══
  const SITES = [
    { name: "WhatsApp",    host: "web.whatsapp.com",    abbr: "Wa", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"  },
    { name: "Instagram",   host: "www.instagram.com",   abbr: "Ig", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"  },
    { name: "Telegram",    host: "web.telegram.org",    abbr: "Tg", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"  },
    { name: "Messenger",   host: "www.messenger.com",   abbr: "Me", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"   },
    { name: "Discord",     host: "discord.com",         abbr: "Dc", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)" },
    { name: "Slack",       host: "app.slack.com",       abbr: "Sl", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"  },
    { name: "X / Twitter", host: "x.com",               abbr: "X",  color: "#FFFFFF", bg: "rgba(255,255,255,0.08)" },
    { name: "Facebook",    host: "www.facebook.com",    abbr: "Fb", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"  },
    { name: "LinkedIn",    host: "www.linkedin.com",    abbr: "Li", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"  },
    { name: "Gmail",       host: "mail.google.com",     abbr: "Gm", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"   },
    { name: "Outlook",     host: "outlook.live.com",    abbr: "Ol", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"   },
    { name: "Teams",       host: "teams.microsoft.com", abbr: "Te", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"  },
    { name: "Element",     host: "app.element.io",      abbr: "El", color: "#FFFFFF", bg: "rgba(255,255,255,0.08)"  },
  ];
  const PREDEFINED_HOSTS = new Set(SITES.map(s => s.host));

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

  const bioDot            = document.getElementById("bioDot");
  const bioStatusText     = document.getElementById("bioStatusText");
  const bioActionBtn      = document.getElementById("bioActionBtn");
  const autoRelockToggle  = document.getElementById("autoRelockToggle");

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
        if (resp.os === 'mac') {
          chrome.storage.local.get(["ms_webauthn_cred_id"], (r) => {
            if (r.ms_webauthn_cred_id) mTouchIDBtn.style.display = "flex";
          });
        }
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
        <div class="site-icon" style="background:var(--accent-bg);color:var(--accent);border:1px solid var(--accent-brd);width:28px;height:28px;border-radius:7px;font-size:9.5px;font-weight:800;flex-shrink:0;display:flex;align-items:center;justify-content:center;">${host[0].toUpperCase()}</div>
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
          <div class="site-icon" style="background:${site.bg};color:${site.color};">${site.abbr}</div>
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
            pwMsg.textContent = "Set a password first to enable App Lock";
            pwMsg.className = "pw-msg err";
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
  // TOUCH ID
  // ═══════════════════════════════════════

  let bioEnrolled = false;

  function loadBioState() {
    chrome.runtime.getPlatformInfo((info) => {
      if (info.os !== 'mac') {
        const bioLabel = document.querySelector(".bio-label");
        if (bioLabel) bioLabel.textContent = "Windows Hello / Touch ID";
        bioDot.classList.remove("enrolled");
        bioStatusText.textContent = "Coming Soon";
        bioActionBtn.textContent = "Coming Soon";
        bioActionBtn.className = "btn btn-ghost";
        bioActionBtn.style.cssText = "font-size:11.5px;height:32px;padding:0 12px;opacity:0.5;";
        bioActionBtn.disabled = true;
        return;
      }
      chrome.storage.local.get(["ms_webauthn_cred_id"], (r) => {
        bioEnrolled = !!r.ms_webauthn_cred_id;
        if (bioEnrolled) {
          bioDot.classList.add("enrolled");
          bioStatusText.textContent = "Enrolled and ready";
          bioActionBtn.textContent = "Reset";
          bioActionBtn.className = "btn btn-danger";
          bioActionBtn.style.cssText = "font-size:11.5px;height:32px;padding:0 12px;";
        } else {
          bioDot.classList.remove("enrolled");
          bioStatusText.textContent = "Not enrolled";
          bioActionBtn.textContent = "Enroll";
          bioActionBtn.className = "btn btn-ghost";
          bioActionBtn.style.cssText = "font-size:11.5px;height:32px;padding:0 12px;";
        }
        bioActionBtn.disabled = false;
      });
    });
  }
  loadBioState();

  bioActionBtn.addEventListener("click", () => {
    if (bioEnrolled) {
      if (bioActionBtn.textContent === "Reset") {
        bioActionBtn.textContent = "Confirm Reset";
        setTimeout(() => { if (bioEnrolled) bioActionBtn.textContent = "Reset"; }, 3000);
        return;
      }
      bioActionBtn.textContent = "Resetting…";
      chrome.storage.local.remove(["ms_webauthn_cred_id"], () => loadBioState());
    } else {
      bioActionBtn.disabled = true;
      bioActionBtn.textContent = "Opening…";
      chrome.runtime.sendMessage({ action: "ms_openTouchID", hostname: "_setup", mode: "enroll" }, () => {
        let attempts = 0;
        const poll = setInterval(() => {
          attempts++;
          chrome.storage.local.get(["ms_webauthn_cred_id"], (r) => {
            if (r.ms_webauthn_cred_id || attempts > 30) { clearInterval(poll); loadBioState(); }
          });
        }, 1000);
      });
    }
  });

  // ═══ Auto-relock ═══
  chrome.storage.local.get(["ms_auto_relock"], (r) => {
    autoRelockToggle.checked = r.ms_auto_relock === true;
  });
  autoRelockToggle.addEventListener("change", () => {
    chrome.storage.local.set({ ms_auto_relock: autoRelockToggle.checked });
  });

})();
