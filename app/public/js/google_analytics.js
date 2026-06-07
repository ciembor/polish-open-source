(() => {
  const meta = document.querySelector('meta[name="google-analytics-measurement-id"]');
  const measurementId = meta && meta.content.trim();
  if (!measurementId) return;

  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function gtag() {
    window.dataLayer.push(arguments);
  };

  window.gtag("js", new Date());
  window.gtag("config", measurementId);
})();
