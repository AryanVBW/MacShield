/**
 * MacShield — Lock Guard v3.1
 *
 * Runs at document_start on ALL URLs (via host_permissions: <all_urls>).
 *
 * Flow:
 *  1. Immediately hide <html> to prevent any content flash
 *  2. Ask background.js for lock state of this hostname
 *  3. Not locked → un-hide and exit (fast path, most pages)
 *  4. Locked + already unlocked this session → un-hide, set up auto-relock
 *  5. Locked + not unlocked → inject full-screen overlay, then un-hide
 *
 * Overlay is protected by a MutationObserver so SPAs can't remove it.
 */

(function () {
  "use strict";

  const HOST = location.hostname;
  if (!HOST) { return; } // no-op on about:blank, chrome://, etc.

  let autoRelockSetup = false;
  let overlayEl       = null;
  let bodyObserver    = null;

  // ─── Step 1: Hide immediately to prevent content flash ───
  document.documentElement.style.setProperty("visibility", "hidden", "important");

  // ─── Step 2: Check lock state via background ───
  chrome.runtime.sendMessage({ action: "ms_getLockState", hostname: HOST }, (resp) => {
    if (chrome.runtime.lastError || !resp) {
      // Extension context issue or not a locked site — show the page
      show();
      return;
    }

    if (!resp.isLocked) {
      show();
      return;
    }

    if (resp.isUnlocked) {
      // Previously unlocked this session — show and set up auto-relock
      show();
      setupAutoRelockIfEnabled();
      return;
    }

    if (!resp.hasPassword) {
      // Marked as locked but no password set yet — let through
      show();
      return;
    }

    // ─── Locked and not authenticated → inject overlay ───
    injectLockScreen(resp.os);
  });

  // ─── Reveal the page ───
  function show() {
    document.documentElement.style.removeProperty("visibility");
  }

  // ─── Auto-relock when tab goes to background ───
  function setupAutoRelockIfEnabled() {
    if (autoRelockSetup) return;
    chrome.storage.local.get(["ms_auto_relock"], (r) => {
      if (!r.ms_auto_relock) return;
      autoRelockSetup = true;
      document.addEventListener("visibilitychange", function () {
        if (document.visibilityState === "hidden") {
          chrome.runtime.sendMessage({ action: "ms_relock", hostname: HOST });
        }
      });
    });
  }

  // ─── Inject lock screen ───
  function injectLockScreen(os) {
    if (document.body) {
      buildOverlay(os);
    } else {
      document.addEventListener("DOMContentLoaded", () => buildOverlay(os), { once: true });
    }
  }

  function buildOverlay(os) {
    show(); // page is invisible behind the overlay

    overlayEl = document.createElement("div");
    overlayEl.id = "macshield-lock-overlay";
    overlayEl.setAttribute("data-macshield", "true");

    overlayEl.innerHTML = `
      <div class="ms-lock-card">

        <div class="ms-lock-logo">
          <img src="${chrome.runtime.getURL('icons/logo.svg')}" alt="MacShield" style="width:100%; height:100%;">
        </div>

        <h1 class="ms-lock-title">MacShield</h1>
        <p class="ms-lock-subtitle">This page is locked</p>
        <div class="ms-lock-host">${HOST}</div>

        <div class="ms-lock-input-wrap">
          <input type="password" id="msPasswordInput" class="ms-lock-input"
                 placeholder="Password or PIN" autocomplete="off" spellcheck="false">
          <button id="msUnlockBtn" class="ms-lock-btn ms-lock-btn-primary">Unlock</button>
        </div>

        <div class="ms-lock-error" id="msLockError">Incorrect password — try again.</div>

        <div class="ms-lock-divider" ${os !== 'mac' ? 'style="display:none;"' : ''}><span>or</span></div>

        <button id="msTouchIDBtn" class="ms-lock-btn ms-lock-btn-biometric" ${os !== 'mac' ? 'style="display:none;"' : ''}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
            <path d="M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4"/><path d="M14 13.12c0 2.38 0 6.38-1 8.88"/><path d="M17.29 21.02c.12-.6.43-2.3-.5-3.02"/><path d="M2 12a10 10 0 0 1 18-6"/><path d="M2 16h.01"/><path d="M21.8 16c.2-2 .131-5.354 0-6"/><path d="M5 19.5C5.5 18 6 15 6 12a6 6 0 0 1 .34-2"/><path d="M8.65 22c.21-.66.45-1.32.57-2"/><path d="M9 6.8a6 6 0 0 1 9 5.2v2"/>
          </svg>
          Use Touch ID
        </button>
        ${os !== 'mac' ? '<div style="font-size: 11px; color: rgba(255,255,255,0.4); margin-top: 10px;">Touch ID / Windows Hello coming soon</div>' : ''}

        <p class="ms-lock-hint">Protected by MacShield</p>
      </div>
    `;

    document.body.appendChild(overlayEl);
    document.body.style.setProperty("overflow", "hidden", "important");

    // ── Guard: prevent the page from removing the overlay ──
    bodyObserver = new MutationObserver(() => {
      if (!document.getElementById("macshield-lock-overlay")) {
        document.body.appendChild(overlayEl);
      }
    });
    bodyObserver.observe(document.body, { childList: true });

    const pwInput   = document.getElementById("msPasswordInput");
    const unlockBtn = document.getElementById("msUnlockBtn");
    const errorEl   = document.getElementById("msLockError");
    const touchBtn  = document.getElementById("msTouchIDBtn");

    setTimeout(() => pwInput && pwInput.focus(), 80);

    // ── Password unlock ──
    function attemptUnlock() {
      const pw = pwInput.value;
      if (!pw) {
        shake(pwInput);
        return;
      }

      unlockBtn.disabled = true;
      unlockBtn.textContent = "Checking…";

      chrome.runtime.sendMessage(
        { action: "ms_verifyPassword", password: pw, hostname: HOST },
        (resp) => {
          if (resp && resp.ok) {
            dismissOverlay();
          } else {
            errorEl.style.display = "block";
            pwInput.value = "";
            pwInput.focus();
            shake(pwInput);
            unlockBtn.disabled = false;
            unlockBtn.textContent = "Unlock";
          }
        }
      );
    }

    unlockBtn.addEventListener("click", attemptUnlock);
    pwInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); attemptUnlock(); }
      if (errorEl.style.display !== "none") errorEl.style.display = "none";
    });

    // ── Touch ID ──
    touchBtn.addEventListener("click", () => {
      touchBtn.disabled = true;
      touchBtn.textContent = "Waiting for Touch ID…";
      chrome.runtime.sendMessage({ action: "ms_openTouchID", hostname: HOST }, () => {
        setTimeout(() => {
          touchBtn.disabled = false;
          touchBtn.innerHTML = `
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
              <path d="M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4"/><path d="M14 13.12c0 2.38 0 6.38-1 8.88"/><path d="M17.29 21.02c.12-.6.43-2.3.5-3.02"/><path d="M2 12a10 10 0 0 1 18-6"/><path d="M2 16h.01"/><path d="M21.8 16c.2-2 .131-5.354 0-6"/><path d="M5 19.5C5.5 18 6 15 6 12a6 6 0 0 1 .34-2"/><path d="M8.65 22c.21-.66.45-1.32.57-2"/><path d="M9 6.8a6 6 0 0 1 9 5.2v2"/>
            </svg>
            Use Touch ID`;
        }, 3000);
      });
    });

    // Block keyboard events from reaching the page behind
    overlayEl.addEventListener("keydown", (e) => e.stopPropagation(), true);
    overlayEl.addEventListener("keyup",   (e) => e.stopPropagation(), true);
    overlayEl.addEventListener("keypress",(e) => e.stopPropagation(), true);

    // Trap focus inside overlay
    document.addEventListener("focusin", trapFocus, true);
  }

  function trapFocus(e) {
    if (overlayEl && !overlayEl.contains(e.target)) {
      e.preventDefault();
      e.stopPropagation();
      const pwInput = document.getElementById("msPasswordInput");
      if (pwInput) pwInput.focus();
    }
  }

  function shake(el) {
    el.classList.add("ms-shake");
    setTimeout(() => el.classList.remove("ms-shake"), 500);
  }

  function dismissOverlay() {
    if (bodyObserver) { bodyObserver.disconnect(); bodyObserver = null; }
    document.removeEventListener("focusin", trapFocus, true);

    if (overlayEl) {
      overlayEl.classList.add("ms-lock-fadeout");
      setTimeout(() => {
        if (overlayEl && overlayEl.parentNode) overlayEl.remove();
        overlayEl = null;
        document.body.style.removeProperty("overflow");
        setupAutoRelockIfEnabled();
      }, 350);
    }
  }

  // ─── Listen for messages from background ───
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.action === "ms_unlocked") {
      dismissOverlay();
    }

    if (msg.action === "ms_relocked") {
      if (!document.getElementById("macshield-lock-overlay")) {
        location.reload();
      }
    }
  });

})();
