// MacShield Web — Popup Script

const STORAGE_KEY = "macshield_enabled";
const BLUR_AMOUNT_KEY = "macshield_blur";

const toggle = document.getElementById("blurToggle");
const slider = document.getElementById("blurSlider");
const blurValue = document.getElementById("blurValue");

// Load current state
chrome.storage.sync.get([STORAGE_KEY, BLUR_AMOUNT_KEY], (result) => {
  toggle.checked = result[STORAGE_KEY] !== false;
  const amount = typeof result[BLUR_AMOUNT_KEY] === "number" ? result[BLUR_AMOUNT_KEY] : 8;
  slider.value = amount;
  blurValue.textContent = amount + "px";
});

// Toggle blur on/off
toggle.addEventListener("change", () => {
  chrome.storage.sync.set({ [STORAGE_KEY]: toggle.checked });
});

// Adjust blur intensity
slider.addEventListener("input", () => {
  const amount = parseInt(slider.value, 10);
  blurValue.textContent = amount + "px";
  chrome.storage.sync.set({ [BLUR_AMOUNT_KEY]: amount });
});
