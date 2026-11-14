// MathJax configuration for pymdownx.arithmatex (generic mode).
window.MathJax = {
  tex: {
    inlineMath: [["\(", "\)"]],
    displayMath: [["\[", "\]"]],
    processEscapes: true,
    processEnvironments: true
  },
  options: {
    ignoreHtmlClass: ".*|",
    processHtmlClass: "arithmatex"
  }
};
