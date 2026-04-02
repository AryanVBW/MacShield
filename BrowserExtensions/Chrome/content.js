// MacShield Web — Content Script
// Manages blur state, keyboard shortcut (Alt+X), and dynamic content observation.

(function () {
  "use strict";

  const STORAGE_KEY = "macshield_enabled";
  const BLUR_AMOUNT_KEY = "macshield_blur";

  let isEnabled = true;
  let blurAmount = 8;

  // Load state from storage
  chrome.storage.sync.get([STORAGE_KEY, BLUR_AMOUNT_KEY], (result) => {
    if (result[STORAGE_KEY] === false) {
      isEnabled = false;
      document.body.classList.add("macshield-disabled");
    }
    if (typeof result[BLUR_AMOUNT_KEY] === "number") {
      blurAmount = result[BLUR_AMOUNT_KEY];
      document.documentElement.style.setProperty(
        "--gv-blur",
        blurAmount + "px"
      );
    }
  });

  // Listen for storage changes (from popup toggle)
  chrome.storage.onChanged.addListener((changes) => {
    if (changes[STORAGE_KEY]) {
      isEnabled = changes[STORAGE_KEY].newValue !== false;
      if (isEnabled) {
        document.body.classList.remove("macshield-disabled");
      } else {
        document.body.classList.add("macshield-disabled");
      }
    }
    if (changes[BLUR_AMOUNT_KEY]) {
      blurAmount = changes[BLUR_AMOUNT_KEY].newValue || 8;
      document.documentElement.style.setProperty(
        "--gv-blur",
        blurAmount + "px"
      );
    }
  });

  // Keyboard shortcut: Alt+X to toggle blur
  document.addEventListener("keydown", (e) => {
    if (e.altKey && e.key.toLowerCase() === "x") {
      e.preventDefault();
      isEnabled = !isEnabled;
      chrome.storage.sync.set({ [STORAGE_KEY]: isEnabled });

      if (isEnabled) {
        document.body.classList.remove("macshield-disabled");
      } else {
        document.body.classList.add("macshield-disabled");
      }
    }
  });

  // MutationObserver to handle dynamically loaded content
  // (chat apps lazy-load messages as you scroll)
  const observer = new MutationObserver(() => {
    // CSS handles the blur via selectors — no JS manipulation needed.
    // This observer exists as a hook for future platform-specific logic.
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
  });
})();
