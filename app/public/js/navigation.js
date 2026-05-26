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

let resizeFrame = 0;
let originalSecondaryControls = null;

function secondaryControls(nav) {
  if (!originalSecondaryControls) {
    originalSecondaryControls = Array.from(nav.querySelectorAll(".js-secondary-control"));
  }

  return originalSecondaryControls;
}

function restoreNavItems(nav) {
  const primaryCitySlot = nav.querySelector(".js-primary-city-slot");
  const secondaryControlsSlot = nav.querySelector(".js-secondary-controls-slot");
  const moreCitiesPanel = nav.querySelector(".js-more-cities-panel");
  const hamburgerPanel = nav.querySelector(".js-hamburger-panel");

  if (primaryCitySlot) {
    moveChildren(Array.from(nav.querySelectorAll(".js-primary-city")), primaryCitySlot);
  }
  if (secondaryControlsSlot) {
    moveChildren(secondaryControls(nav), secondaryControlsSlot);
  }
  if (moreCitiesPanel) {
    moveChildren(Array.from(moreCitiesPanel.querySelectorAll(".js-secondary-city")), moreCitiesPanel);
  }
  if (hamburgerPanel) hamburgerPanel.replaceChildren();
}

function visibleNavItems(nav) {
  return [
    ...nav.querySelectorAll(":scope > .nav__link"),
    ...nav.querySelectorAll(".js-primary-city-slot > .js-primary-city"),
    nav.querySelector(".js-more-cities"),
    ...nav.querySelectorAll(".js-secondary-controls-slot > .js-secondary-control"),
    nav.querySelector(".js-hamburger:not([hidden])"),
    ...nav.querySelectorAll(":scope > .js-fixed-control")
  ].filter(Boolean);
}

function navOverflows(nav) {
  const navRect = nav.getBoundingClientRect();
  const childRects = visibleNavItems(nav).map((child) => child.getBoundingClientRect());

  return childRects.some((rect) => rect.left < navRect.left - 1 || rect.right > navRect.right + 1);
}

function moveLastPrimaryCity(nav) {
  const overflowCitySlot = nav.querySelector(".js-overflow-city-slot");
  const primaryCities = Array.from(nav.querySelectorAll(".js-primary-city-slot .js-primary-city"));
  const city = primaryCities[primaryCities.length - 1];
  if (!city || !overflowCitySlot) return false;

  overflowCitySlot.insertBefore(city, overflowCitySlot.firstChild);
  return true;
}

function moveCollapsibleControlToHamburger(nav) {
  const secondaryControlsSlot = nav.querySelector(".js-secondary-controls-slot");
  const hamburgerPanel = nav.querySelector(".js-hamburger-panel");
  if (!secondaryControlsSlot || !hamburgerPanel) return false;

  const controls = Array.from(secondaryControlsSlot.querySelectorAll(".js-collapsible-control"));
  const control = controls[controls.length - 1];
  if (!control) return false;

  hamburgerPanel.insertBefore(control, hamburgerPanel.firstChild);
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

  while (navOverflows(nav) && moveCollapsibleControlToHamburger(nav)) {
    updateHamburger(nav);
  }

  updateHamburger(nav);
}

function scheduleNavLayout() {
  if (resizeFrame) window.cancelAnimationFrame(resizeFrame);
  resizeFrame = window.requestAnimationFrame(() => {
    resizeFrame = 0;
    ensureNavLayout();
  });
}

function revealFirstVisitNotices() {
  document.querySelectorAll(".js-first-visit-notice").forEach((notice) => {
    const storageKey = notice.dataset.storageKey;
    if (!storageKey) return;

    try {
      if (window.localStorage.getItem(storageKey)) {
        notice.remove();
        return;
      }

      window.localStorage.setItem(storageKey, "1");
      notice.hidden = false;
    } catch (_error) {
      notice.remove();
    }
  });
}

window.addEventListener("resize", scheduleNavLayout);

window.addEventListener("DOMContentLoaded", () => {
  revealFirstVisitNotices();
  ensureNavLayout();
});

window.addEventListener("load", ensureNavLayout);
