// Browsers don't scroll a wide table sideways to a link focused inside it.
document.addEventListener("focusin", (event) => {
  if (event.target.matches(".table-wrapper a")) {
    event.target.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "instant" });
  }
});
