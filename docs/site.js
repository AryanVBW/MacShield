(function () {
  const nav = document.querySelector(".nav");
  const menu = document.querySelector("[data-menu-toggle]");
  const theme = document.querySelector("[data-theme-toggle]");

  if (menu && nav) {
    menu.addEventListener("click", () => {
      const open = nav.getAttribute("data-open") === "true";
      nav.setAttribute("data-open", String(!open));
      menu.setAttribute("aria-expanded", String(!open));
    });
  }

  const savedTheme = localStorage.getItem("macshield-theme");
  if (savedTheme === "light" || savedTheme === "dark") {
    document.body.dataset.theme = savedTheme;
  }

  if (theme) {
    theme.addEventListener("click", () => {
      const next = document.body.dataset.theme === "light" ? "dark" : "light";
      document.body.dataset.theme = next;
      localStorage.setItem("macshield-theme", next);
      track("theme_toggle", { theme: next });
    });
  }

  // Google Analytics 4 — marketing website only.
  // The macOS app and Chrome extension contain no analytics.
  const GA_ID = "G-YGX09JKW2R";
  const tag = document.createElement("script");
  tag.async = true;
  tag.src = "https://www.googletagmanager.com/gtag/js?id=" + GA_ID;
  document.head.appendChild(tag);
  window.dataLayer = window.dataLayer || [];
  window.gtag = function () { window.dataLayer.push(arguments); };
  gtag("js", new Date());
  gtag("config", GA_ID, { anonymize_ip: true });

  function track(name, params) {
    if (typeof gtag === "function") gtag("event", name, params || {});
  }

  // Delegated click tracking for downloads, outbound links, and nav.
  document.addEventListener("click", function (e) {
    const a = e.target.closest("a");
    if (!a || !a.href) return;
    const href = a.href;
    const label = (a.getAttribute("aria-label") || a.textContent || "").trim().slice(0, 80);
    const location = a.closest(".nav") ? "nav"
      : a.closest(".hero") ? "hero"
      : a.closest(".footer") ? "footer"
      : "body";

    if (/apps\.apple\.com/.test(href)) {
      track("download_macos", { link_url: href, link_text: label, location: location });
    } else if (/chromewebstore\.google\.com/.test(href)) {
      track("download_chrome", { link_url: href, link_text: label, location: location });
    } else if (/github\.com\/AryanVBW\/MacShield\/releases/.test(href)) {
      track("download_github", { link_url: href, link_text: label, location: location });
    } else if (/github\.com/.test(href)) {
      track("github_click", { link_url: href, link_text: label, location: location });
    } else if (a.host && a.host !== window.location.host) {
      track("outbound_click", { link_url: href, link_text: label, location: location });
    } else if (location === "nav") {
      track("nav_click", { link_url: href, link_text: label });
    }
  });
})();
