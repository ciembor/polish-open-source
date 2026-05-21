document.addEventListener("click", (event) => {
  document.querySelectorAll(".nav-menu[open]").forEach((menu) => {
    if (!menu.contains(event.target)) {
      menu.removeAttribute("open");
    }
  });
});

function moveChildren(children, destination) {
  children.forEach((node) => destination.appendChild(node));
}

function moveChildrenBefore(children, destination, beforeNode) {
  children.forEach((node) => destination.insertBefore(node, beforeNode));
}

function ensureNavLayout() {
  const nav = document.querySelector(".js-nav");
  if (!nav) return;

  const primaryCities = Array.from(nav.querySelectorAll(".js-primary-city"));
  const secondaryLinks = Array.from(nav.querySelectorAll(".js-secondary-link"));
  const primaryCitySlot = nav.querySelector(".js-primary-city-slot");
  const secondaryLinksSlot = nav.querySelector(".js-secondary-links-slot");

  const moreCitiesPanel = nav.querySelector(".js-more-cities-panel");
  const hamburger = nav.querySelector(".js-hamburger");
  const hamburgerPanel = nav.querySelector(".js-hamburger-panel");

  if (!moreCitiesPanel || !hamburger || !hamburgerPanel) return;

  if (primaryCitySlot) moveChildren(primaryCities, primaryCitySlot);
  if (secondaryLinksSlot) moveChildren(secondaryLinks, secondaryLinksSlot);
  hamburger.hidden = true;
  hamburger.removeAttribute("open");

  const navItems = Array.from(
    nav.querySelectorAll("a, details, form, button, .language-switch")
  ).filter((node) => !node.hidden);
  const firstRowTop = navItems.length ? navItems[0].offsetTop : nav.offsetTop;
  const isNarrow = navItems.some((node) => node.offsetTop > firstRowTop + 1);

  if (isNarrow) {
    if (primaryCitySlot) {
      const firstSecondaryCity = moreCitiesPanel.querySelector(".js-secondary-city");
      if (firstSecondaryCity) {
        moveChildrenBefore(primaryCities, moreCitiesPanel, firstSecondaryCity);
      } else {
        moveChildren(primaryCities, moreCitiesPanel);
      }
    }
    if (secondaryLinksSlot) moveChildren(secondaryLinks, hamburgerPanel);
    hamburger.hidden = hamburgerPanel.children.length === 0;
    return;
  }
}

window.addEventListener("resize", () => {
  ensureNavLayout();
});

window.addEventListener("DOMContentLoaded", () => {
  ensureNavLayout();
});
