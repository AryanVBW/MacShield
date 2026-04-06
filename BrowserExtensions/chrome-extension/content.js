/**
 * MacShield — Blur Content Script v3.0
 * Runs at document_idle. Handles blur/hide activation, profile picture
 * blurring, keyboard shortcuts, and dynamic element watching.
 *
 * (Lock guard is handled separately by lock-guard.js at document_start)
 */

(function () {
  "use strict";

  const SITE_KEY = "macshield_" + location.hostname.replace(/\./g, "_");

  // Apply blur CSS variables
  function applyBlurSettings(level, hideMode) {
    const root = document.documentElement;
    if (hideMode) {
      root.style.setProperty("--pb-blur", "0px");
      root.style.setProperty("--pb-opacity", "0");
    } else {
      root.style.setProperty("--pb-blur", level + "px");
      root.style.setProperty("--pb-opacity", "1");
    }
  }

  // Load saved settings
  chrome.storage.local.get(
    [SITE_KEY, "ms_blur_level", "ms_blur_avatars", "ms_hide_mode"],
    (result) => {
      const isActive    = result[SITE_KEY] !== false;
      const blurLevel   = result["ms_blur_level"] || 12;
      const blurAvatars = result["ms_blur_avatars"] === true;
      const hideMode    = result["ms_hide_mode"] === true;

      applyBlurSettings(blurLevel, hideMode);
      if (blurAvatars) document.body.classList.add("privyblur-blur-avatars");
      if (isActive)    document.body.classList.add("privyblur-active");
    }
  );

  // Message handler from popup & background
  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.action === "toggle") {
      const isActive = document.body.classList.toggle("privyblur-active");
      chrome.storage.local.set({ [SITE_KEY]: isActive });
      sendResponse({ active: isActive });
    }

    if (msg.action === "getState") {
      chrome.storage.local.get(
        ["ms_blur_level", "ms_blur_avatars", "ms_hide_mode"],
        (result) => {
          sendResponse({
            active:      document.body.classList.contains("privyblur-active"),
            blurLevel:   result["ms_blur_level"] || 12,
            blurAvatars: result["ms_blur_avatars"] === true,
            hideMode:    result["ms_hide_mode"] === true,
          });
        }
      );
      return true; // async
    }

    if (msg.action === "setBlurLevel") {
      chrome.storage.local.get(["ms_hide_mode"], (result) => {
        chrome.storage.local.set({ ms_blur_level: msg.level });
        applyBlurSettings(msg.level, result["ms_hide_mode"] === true);
      });
      sendResponse({ ok: true });
    }

    if (msg.action === "setBlurAvatars") {
      document.body.classList.toggle("privyblur-blur-avatars", msg.enabled);
      chrome.storage.local.set({ ms_blur_avatars: msg.enabled });
      sendResponse({ ok: true });
    }

    if (msg.action === "setHideMode") {
      chrome.storage.local.get(["ms_blur_level"], (result) => {
        chrome.storage.local.set({ ms_hide_mode: msg.enabled });
        applyBlurSettings(result["ms_blur_level"] || 12, msg.enabled);
      });
      sendResponse({ ok: true });
    }

    return true;
  });

  // Keyboard shortcut: Alt+X to toggle blur
  document.addEventListener("keydown", (e) => {
    if (e.altKey && e.key.toLowerCase() === "x") {
      e.preventDefault();
      const isActive = document.body.classList.toggle("privyblur-active");
      chrome.storage.local.set({ [SITE_KEY]: isActive });
    }
  });

  // MutationObserver for unknown sites
  const KNOWN_SITES = new Set([
    "web.whatsapp.com", "www.instagram.com", "web.telegram.org",
    "www.messenger.com", "discord.com", "app.slack.com",
    "twitter.com", "x.com", "www.linkedin.com", "mail.google.com",
    "teams.microsoft.com", "www.facebook.com", "signal.group", "app.element.io",
    "outlook.live.com", "outlook.office.com",
  ]);

  if (!KNOWN_SITES.has(location.hostname)) {
    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType !== 1) continue;
          const candidates = node.querySelectorAll
            ? node.querySelectorAll(
                '[class*="message"], [class*="chat"], [class*="msg"], ' +
                '[data-message-id], [class*="bubble"], [class*="conversation"]'
              )
            : [];
          candidates.forEach((el) => {
            if (!el.classList.contains("pb-blur-target")) {
              el.classList.add("pb-blur-target");
              if (el.parentElement) el.parentElement.classList.add("pb-blur-parent");
            }
          });
        }
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }

  console.log(
    "%c🛡️ MacShield v3 active on " + location.hostname + " — Alt+X to toggle blur",
    "color:#2196F3;font-weight:bold;font-size:13px;"
  );
})();
