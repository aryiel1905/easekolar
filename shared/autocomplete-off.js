(() => {
  const applyAutocompleteOff = (root = document) => {
    root.querySelectorAll("form, input, textarea, select").forEach((el) => {
      el.setAttribute("autocomplete", "off");
    });
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => applyAutocompleteOff(document), { once: true });
  } else {
    applyAutocompleteOff(document);
  }

  const observer = new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      mutation.addedNodes.forEach((node) => {
        if (!(node instanceof Element)) return;
        if (node.matches("form, input, textarea, select")) {
          node.setAttribute("autocomplete", "off");
        }
        applyAutocompleteOff(node);
      });
    });
  });

  observer.observe(document.documentElement, { childList: true, subtree: true });
})();
