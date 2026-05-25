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

function restoreNavItems(nav) {
  const primaryCitySlot = nav.querySelector(".js-primary-city-slot");
  const secondaryLinksSlot = nav.querySelector(".js-secondary-links-slot");
  const moreCitiesPanel = nav.querySelector(".js-more-cities-panel");
  const hamburgerPanel = nav.querySelector(".js-hamburger-panel");

  if (primaryCitySlot) {
    moveChildren(Array.from(nav.querySelectorAll(".js-primary-city")), primaryCitySlot);
  }
  if (secondaryLinksSlot) {
    moveChildren(Array.from(nav.querySelectorAll(".js-secondary-link")), secondaryLinksSlot);
  }
  if (moreCitiesPanel) {
    moveChildren(Array.from(moreCitiesPanel.querySelectorAll(".js-secondary-city")), moreCitiesPanel);
  }
  if (hamburgerPanel) hamburgerPanel.replaceChildren();
}

function navOverflows(nav) {
  const header = nav.closest(".site-header__inner");
  if (!header) return nav.scrollWidth > nav.clientWidth;

  const headerStyle = window.getComputedStyle(header);
  const columnGap = parseFloat(headerStyle.columnGap || headerStyle.gap || "0") || 0;
  const brand = header.querySelector(".brand");
  const brandWidth = brand ? brand.getBoundingClientRect().width : 0;
  const availableWidth = header.clientWidth - brandWidth - columnGap;

  return nav.scrollWidth > Math.floor(availableWidth);
}

function moveLastPrimaryCity(nav) {
  const moreCitiesPanel = nav.querySelector(".js-more-cities-panel");
  const firstSecondaryCity = moreCitiesPanel && moreCitiesPanel.querySelector(".js-secondary-city");
  const primaryCities = Array.from(nav.querySelectorAll(".js-primary-city"));
  const city = primaryCities[primaryCities.length - 1];
  if (!city || !moreCitiesPanel) return false;

  if (firstSecondaryCity) {
    moreCitiesPanel.insertBefore(city, firstSecondaryCity);
  } else {
    moreCitiesPanel.appendChild(city);
  }
  return true;
}

function moveSecondaryLinkToHamburger(nav) {
  const secondaryLinks = Array.from(nav.querySelectorAll(".js-secondary-links-slot .js-secondary-link"));
  const link = secondaryLinks[secondaryLinks.length - 1];
  const hamburgerPanel = nav.querySelector(".js-hamburger-panel");
  if (!link || !hamburgerPanel) return false;

  hamburgerPanel.insertBefore(link, hamburgerPanel.firstChild);
  return true;
}

function updateMenuLabels(nav) {
  const moreCitiesSummary = nav.querySelector(".js-more-cities-summary");
  const hasPrimaryCities = nav.querySelectorAll(".js-primary-city-slot .js-primary-city").length > 0;
  if (moreCitiesSummary) {
    moreCitiesSummary.textContent = hasPrimaryCities
      ? moreCitiesSummary.dataset.labelWide
      : moreCitiesSummary.dataset.labelNarrow;
  }
}

function shortenMoreCitiesLabel(nav) {
  const moreCitiesSummary = nav.querySelector(".js-more-cities-summary");
  if (!moreCitiesSummary) return false;
  if (moreCitiesSummary.textContent === moreCitiesSummary.dataset.labelNarrow) return false;

  moreCitiesSummary.textContent = moreCitiesSummary.dataset.labelNarrow;
  return true;
}

function updateHamburger(nav) {
  const hamburger = nav.querySelector(".js-hamburger");
  const hamburgerPanel = nav.querySelector(".js-hamburger-panel");
  if (!hamburger || !hamburgerPanel) return;

  hamburger.hidden = hamburgerPanel.children.length === 0;
  if (hamburger.hidden) hamburger.removeAttribute("open");
}

function ensureNavLayout() {
  const nav = document.querySelector(".js-nav");
  if (!nav) return;

  restoreNavItems(nav);
  updateMenuLabels(nav);
  updateHamburger(nav);

  while (navOverflows(nav) && moveLastPrimaryCity(nav)) {
    updateMenuLabels(nav);
  }

  updateMenuLabels(nav);
  if (navOverflows(nav)) shortenMoreCitiesLabel(nav);

  while (navOverflows(nav) && moveSecondaryLinkToHamburger(nav)) {
    updateHamburger(nav);
  }

  updateHamburger(nav);
}

window.addEventListener("resize", () => {
  window.requestAnimationFrame(ensureNavLayout);
});

window.addEventListener("DOMContentLoaded", () => {
  ensureNavLayout();
});
