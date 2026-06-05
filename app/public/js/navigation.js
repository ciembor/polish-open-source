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
const originalSecondaryControls = new WeakMap();

function secondaryControls(nav) {
  if (!originalSecondaryControls.has(nav)) {
    originalSecondaryControls.set(nav, Array.from(nav.querySelectorAll(".js-secondary-control")));
  }

  return originalSecondaryControls.get(nav);
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

function ensureNavLayout(nav) {
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

function ensureNavLayouts() {
  document.querySelectorAll(".js-nav").forEach(ensureNavLayout);
}

function scheduleNavLayout() {
  if (resizeFrame) window.cancelAnimationFrame(resizeFrame);
  resizeFrame = window.requestAnimationFrame(() => {
    resizeFrame = 0;
    ensureNavLayouts();
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

function fallbackCopyText(text) {
  const input = document.createElement("textarea");
  input.value = text;
  input.setAttribute("readonly", "");
  input.style.position = "fixed";
  input.style.top = "-1000px";
  document.body.appendChild(input);
  input.select();

  try {
    document.execCommand("copy");
  } finally {
    input.remove();
  }
}

function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text).catch(() => {
      fallbackCopyText(text);
    });
  }

  fallbackCopyText(text);
  return Promise.resolve();
}

function markCopyButton(button) {
  const originalLabel = button.dataset.copyLabel || button.textContent;
  button.textContent = button.dataset.copyDoneLabel || originalLabel;
  window.setTimeout(() => {
    button.textContent = originalLabel;
  }, 1600);
}

function handleBadgeMarkdownCopy(event) {
  const button = event.target.closest(".js-copy-badge-markdown");
  if (!button) return;

  copyText(button.dataset.copyText || "").then(() => markCopyButton(button));
}

function profileDeleteModal(button) {
  const target = button.dataset.target;
  return target ? document.querySelector(target) : null;
}

function closeProfileDeleteModal(modal) {
  modal.hidden = true;
}

function handleProfileDeleteModal(event) {
  const openButton = event.target.closest(".js-profile-delete-open");
  if (openButton) {
    const modal = profileDeleteModal(openButton);
    if (modal) {
      event.preventDefault();
      modal.hidden = false;
      modal.querySelector(".js-profile-delete-cancel")?.focus();
    }
    return;
  }

  const cancelButton = event.target.closest(".js-profile-delete-cancel");
  if (cancelButton) {
    closeProfileDeleteModal(cancelButton.closest(".js-profile-delete-modal"));
    return;
  }

  if (event.target.classList.contains("js-profile-delete-modal")) {
    closeProfileDeleteModal(event.target);
  }
}

document.addEventListener("click", handleBadgeMarkdownCopy);
document.addEventListener("click", handleProfileDeleteModal);
window.addEventListener("resize", scheduleNavLayout);

window.addEventListener("DOMContentLoaded", () => {
  revealFirstVisitNotices();
  ensureNavLayouts();
});

window.addEventListener("load", ensureNavLayouts);
