// MacShield Web — Background Service Worker

const K = {
  ENABLED: "macshield_enabled",
  BLUR: "macshield_blur",
  SITES: "macshield_sites",
  REVEAL: "macshield_reveal",
};

// Set defaults on install
chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.sync.get([K.ENABLED], (result) => {
    if (result[K.ENABLED] === undefined) {
      chrome.storage.sync.set({
        [K.ENABLED]: true,
        [K.BLUR]: 8,
        [K.REVEAL]: "hover",
        [K.SITES]: {
          whatsapp: true,
          instagram: true,
          telegram: true,
          discord: true,
          slack: true,
          twitter: true,
          linkedin: true,
          gmail: true,
          teams: true,
          messenger: true,
          messages: true,
        },
      });
    }
  });
  updateBadge(true);
});

// Update badge when state changes
chrome.storage.onChanged.addListener((changes) => {
  if (changes[K.ENABLED]) {
    updateBadge(changes[K.ENABLED].newValue !== false);
  }
});

function updateBadge(enabled) {
  chrome.action.setBadgeText({ text: enabled ? "ON" : "" });
  chrome.action.setBadgeBackgroundColor({ color: enabled ? "#FFD213" : "#666" });
  chrome.action.setBadgeTextColor({ color: "#000" });
}

// Load initial state
chrome.storage.sync.get([K.ENABLED], (result) => {
  updateBadge(result[K.ENABLED] !== false);
});
