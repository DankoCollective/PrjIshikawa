(() => {
  try {
    const storedTheme = localStorage.getItem("ishikawa.theme");
    const preferredTheme = matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    document.documentElement.dataset.theme = storedTheme === "dark" || storedTheme === "light"
      ? storedTheme
      : preferredTheme;
  } catch {
    document.documentElement.dataset.theme = "light";
  }
})();
