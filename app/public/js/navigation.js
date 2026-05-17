document.addEventListener("click", (event) => {
  document.querySelectorAll(".nav-menu[open]").forEach((menu) => {
    if (!menu.contains(event.target)) {
      menu.removeAttribute("open");
    }
  });
});
