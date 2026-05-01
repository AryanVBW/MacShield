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
    });
  }
})();
