// MacShield Web — Content Script
// Per-site blur, keyboard shortcut (Alt+X), hover/click reveal, dynamic content observation.

(function () {
  "use strict";

  const K = {
    ENABLED: "macshield_enabled",
    BLUR: "macshield_blur",
    SITES: "macshield_sites",
    REVEAL: "macshield_reveal",
  };

  // Map hostnames to site IDs
  const SITE_MAP = {
    "web.whatsapp.com": "whatsapp",
    "www.instagram.com": "instagram",
    "web.telegram.org": "telegram",
    "discord.com": "discord",
    "app.slack.com": "slack",
    "x.com": "twitter",
    "twitter.com": "twitter",
    "www.linkedin.com": "linkedin",
    "mail.google.com": "gmail",
    "teams.microsoft.com": "teams",
    "www.messenger.com": "messenger",
    "www.facebook.com": "messenger",
    "messages.google.com": "messages",
  };

  const hostname = window.location.hostname;
  const siteId = SITE_MAP[hostname];
  if (!siteId) return; // Not a supported site

  let isEnabled = true;
  let isSiteEnabled = true;
  let blurAmount = 8;
  let revealMode = "hover";

  // ─── Load State ───
  chrome.storage.sync.get([K.ENABLED, K.BLUR, K.SITES, K.REVEAL], (result) => {
    isEnabled = result[K.ENABLED] !== false;
    blurAmount = typeof result[K.BLUR] === "number" ? result[K.BLUR] : 8;
    revealMode = result[K.REVEAL] || "hover";

    const sites = result[K.SITES] || {};
    isSiteEnabled = sites[siteId] !== false;

    applyState();
  });

  // ─── Listen for Storage Changes ───
  chrome.storage.onChanged.addListener((changes) => {
    if (changes[K.ENABLED]) {
      isEnabled = changes[K.ENABLED].newValue !== false;
    }
    if (changes[K.BLUR]) {
      blurAmount = changes[K.BLUR].newValue || 8;
    }
    if (changes[K.SITES]) {
      const sites = changes[K.SITES].newValue || {};
      isSiteEnabled = sites[siteId] !== false;
    }
    if (changes[K.REVEAL]) {
      revealMode = changes[K.REVEAL].newValue || "hover";
    }
    applyState();
  });

  // ─── Apply State ───
  function applyState() {
    const active = isEnabled && isSiteEnabled;

    document.documentElement.style.setProperty("--gv-blur", blurAmount + "px");

    if (active) {
      document.body.classList.remove("macshield-disabled");
    } else {
      document.body.classList.add("macshield-disabled");
    }

    if (revealMode === "click") {
      document.body.classList.add("macshield-click-mode");
    } else {
      document.body.classList.remove("macshield-click-mode");
      // Remove any click-revealed elements when switching back to hover
      document.querySelectorAll(".macshield-revealed").forEach((el) => {
        el.classList.remove("macshield-revealed");
      });
    }
  }

  // ─── Keyboard Shortcut: Alt+X ───
  document.addEventListener("keydown", (e) => {
    if (e.altKey && e.key.toLowerCase() === "x") {
      e.preventDefault();
      isEnabled = !isEnabled;
      chrome.storage.sync.set({ [K.ENABLED]: isEnabled });
      applyState();
    }
  });

  // ─── Click-to-Reveal Handler ───
  document.addEventListener("click", (e) => {
    if (revealMode !== "click" || !isEnabled || !isSiteEnabled) return;

    // Walk up from the clicked element to find a blurred container
    let target = e.target;
    for (let i = 0; i < 8 && target && target !== document.body; i++) {
      const filter = getComputedStyle(target).filter;
      if (filter && filter.includes("blur")) {
        target.classList.toggle("macshield-revealed");
        return;
      }
      target = target.parentElement;
    }
  });

  // ─── MutationObserver for Dynamic Content ───
  const observer = new MutationObserver(() => {
    // CSS handles blur via selectors — observer is a hook for future logic.
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
  });
})();
