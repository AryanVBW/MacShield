// MacShield Web — Popup Controller

(function () {
  "use strict";

  // ─── Storage Keys ───
  const K = {
    ENABLED: "macshield_enabled",
    BLUR: "macshield_blur",
    SITES: "macshield_sites",
    REVEAL: "macshield_reveal",
    PIN: "macshield_pin",
  };

  // ─── Site Definitions ───
  const SITES = [
    { id: "whatsapp",  name: "WhatsApp Web",     color: "#25D366", letter: "W" },
    { id: "instagram", name: "Instagram",         color: "#E4405F", letter: "I" },
    { id: "telegram",  name: "Telegram",          color: "#0088cc", letter: "T" },
    { id: "discord",   name: "Discord",           color: "#5865F2", letter: "D" },
    { id: "slack",     name: "Slack",             color: "#611f69", letter: "S" },
    { id: "twitter",   name: "X / Twitter",       color: "#1DA1F2", letter: "X" },
    { id: "linkedin",  name: "LinkedIn",          color: "#0A66C2", letter: "L" },
    { id: "gmail",     name: "Gmail",             color: "#EA4335", letter: "G" },
    { id: "teams",     name: "Microsoft Teams",   color: "#6264A7", letter: "T" },
    { id: "messenger", name: "Messenger",         color: "#0084FF", letter: "M" },
    { id: "messages",  name: "Google Messages",   color: "#1A73E8", letter: "G" },
  ];

  // ─── DOM References ───
  const $ = (s) => document.getElementById(s);
  const lockScreen = $("lockScreen");
  const pinInput = $("pinInput");
  const lockError = $("lockError");
  const pinArea = $("pinArea");
  const dots = [0, 1, 2, 3].map((i) => $("dot" + i));

  const blurToggle = $("blurToggle");
  const shieldIcon = $("shieldIcon");
  const statusDot = $("statusDot");
  const statusText = $("statusText");
  const siteCount = $("siteCount");
  const blurLevel = $("blurLevel");

  const blurSlider = $("blurSlider");
  const blurValueDisplay = $("blurValueDisplay");
  const pinToggle = $("pinToggle");
  const pinSetup = $("pinSetup");
  const newPinInput = $("newPin");
  const saveBtn = $("savePin");
  const removeBtn = $("removePin");
  const sitesList = $("sitesList");

  // ─── State ───
  let state = {
    enabled: true,
    blur: 8,
    sites: {},
    reveal: "hover",
    pin: null,
  };

  // ─── Init ───
  chrome.storage.sync.get([K.ENABLED, K.BLUR, K.SITES, K.REVEAL], (sync) => {
    chrome.storage.local.get([K.PIN], (local) => {
      state.enabled = sync[K.ENABLED] !== false;
      state.blur = typeof sync[K.BLUR] === "number" ? sync[K.BLUR] : 8;
      state.sites = sync[K.SITES] || {};
      state.reveal = sync[K.REVEAL] || "hover";
      state.pin = local[K.PIN] || null;

      // Default all sites to enabled
      SITES.forEach((s) => {
        if (state.sites[s.id] === undefined) state.sites[s.id] = true;
      });

      // Show lock screen if PIN is set
      if (state.pin) {
        lockScreen.classList.remove("hidden");
        pinInput.focus();
      }

      renderAll();
    });
  });

  // ─── Render All ───
  function renderAll() {
    renderShield();
    renderSites();
    renderSettings();
  }

  function renderShield() {
    blurToggle.checked = state.enabled;

    if (state.enabled) {
      shieldIcon.classList.remove("disabled");
      shieldIcon.classList.add("shield-pulse");
      statusDot.classList.remove("off");
      statusText.textContent = "Protection Active";
    } else {
      shieldIcon.classList.add("disabled");
      shieldIcon.classList.remove("shield-pulse");
      statusDot.classList.add("off");
      statusText.textContent = "Protection Disabled";
    }

    const activeSites = SITES.filter((s) => state.sites[s.id] !== false).length;
    siteCount.textContent = activeSites;
    blurLevel.textContent = state.blur + "px";
  }

  function renderSites() {
    sitesList.innerHTML = "";
    SITES.forEach((site) => {
      const row = document.createElement("div");
      row.className = "site-row";

      const icon = document.createElement("div");
      icon.className = "site-icon";
      icon.style.background = site.color;
      icon.textContent = site.letter;

      const name = document.createElement("span");
      name.className = "site-name";
      name.textContent = site.name;

      const toggle = document.createElement("label");
      toggle.className = "toggle";
      const input = document.createElement("input");
      input.type = "checkbox";
      input.checked = state.sites[site.id] !== false;
      input.addEventListener("change", () => {
        state.sites[site.id] = input.checked;
        chrome.storage.sync.set({ [K.SITES]: state.sites });
        renderShield();
      });
      const track = document.createElement("span");
      track.className = "toggle-track";
      const thumb = document.createElement("span");
      thumb.className = "toggle-thumb";
      track.appendChild(thumb);
      toggle.appendChild(input);
      toggle.appendChild(track);

      row.appendChild(icon);
      row.appendChild(name);
      row.appendChild(toggle);
      sitesList.appendChild(row);
    });
  }

  function renderSettings() {
    blurSlider.value = state.blur;
    blurValueDisplay.textContent = state.blur + "px";

    // Reveal mode
    document.querySelectorAll(".seg-btn").forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.mode === state.reveal);
    });

    // PIN
    pinToggle.checked = !!state.pin;
    if (state.pin) {
      pinSetup.classList.remove("hidden");
      newPinInput.classList.add("hidden");
      saveBtn.classList.add("hidden");
      removeBtn.classList.remove("hidden");
    } else {
      pinSetup.classList.add("hidden");
    }
  }

  // ─── Tab Navigation ───
  const tabs = document.querySelectorAll(".tab");
  const panels = document.querySelectorAll(".tab-panel");
  const indicator = document.querySelector(".tab-indicator");

  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => t.classList.remove("active"));
      panels.forEach((p) => p.classList.remove("active"));
      tab.classList.add("active");
      document.getElementById("tab" + capitalize(tab.dataset.tab)).classList.add("active");
      indicator.dataset.pos = i;
    });
  });

  function capitalize(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

  // ─── Master Toggle ───
  blurToggle.addEventListener("change", () => {
    state.enabled = blurToggle.checked;
    chrome.storage.sync.set({ [K.ENABLED]: state.enabled });
    renderShield();
  });

  // ─── Blur Slider ───
  blurSlider.addEventListener("input", () => {
    state.blur = parseInt(blurSlider.value, 10);
    blurValueDisplay.textContent = state.blur + "px";
    blurLevel.textContent = state.blur + "px";
    chrome.storage.sync.set({ [K.BLUR]: state.blur });
  });

  // ─── Reveal Mode ───
  document.querySelectorAll(".seg-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".seg-btn").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      state.reveal = btn.dataset.mode;
      chrome.storage.sync.set({ [K.REVEAL]: state.reveal });
    });
  });

  // ─── PIN Lock ───
  pinToggle.addEventListener("change", () => {
    if (pinToggle.checked) {
      pinSetup.classList.remove("hidden");
      newPinInput.classList.remove("hidden");
      saveBtn.classList.remove("hidden");
      removeBtn.classList.add("hidden");
      newPinInput.value = "";
      newPinInput.focus();
    } else {
      state.pin = null;
      chrome.storage.local.set({ [K.PIN]: null });
      pinSetup.classList.add("hidden");
    }
  });

  saveBtn.addEventListener("click", () => {
    const pin = newPinInput.value.trim();
    if (pin.length === 4 && /^\d{4}$/.test(pin)) {
      state.pin = pin;
      chrome.storage.local.set({ [K.PIN]: pin });
      renderSettings();
    } else {
      newPinInput.style.borderColor = "#FF3B30";
      setTimeout(() => { newPinInput.style.borderColor = ""; }, 1500);
    }
  });

  removeBtn.addEventListener("click", () => {
    state.pin = null;
    pinToggle.checked = false;
    chrome.storage.local.set({ [K.PIN]: null });
    renderSettings();
  });

  // ─── Lock Screen PIN Entry ───
  pinArea.addEventListener("click", () => pinInput.focus());

  pinInput.addEventListener("input", () => {
    const val = pinInput.value;
    dots.forEach((d, i) => d.classList.toggle("filled", i < val.length));

    if (val.length === 4) {
      if (val === state.pin) {
        lockScreen.classList.add("hidden");
      } else {
        lockError.classList.add("visible");
        pinArea.classList.add("shake");
        setTimeout(() => {
          pinInput.value = "";
          dots.forEach((d) => d.classList.remove("filled"));
          lockError.classList.remove("visible");
          pinArea.classList.remove("shake");
        }, 800);
      }
    }
  });

  // ─── Header Lock Button ───
  $("lockBtn").addEventListener("click", () => {
    // Navigate to settings tab and focus PIN section
    tabs.forEach((t) => t.classList.remove("active"));
    panels.forEach((p) => p.classList.remove("active"));
    tabs[2].classList.add("active");
    $("tabSettings").classList.add("active");
    indicator.dataset.pos = 2;

    // Highlight PIN section
    if (!state.pin) {
      pinToggle.checked = true;
      pinToggle.dispatchEvent(new Event("change"));
    }
  });
})();
