// Browsers can leave a partly visible link in a wide table cut off at the
// table's edge when it takes keyboard focus. Scroll only the table sideways;
// the page's own scroll stays the browser's. Pointer focus is left alone, so
// the link doesn't move out from under a click or tap.
document.addEventListener("focusin", (event) => {
  if (!(event.target instanceof Element)) return;
  const link = event.target.closest(".table-wrapper a");
  if (!link || !link.matches(":focus-visible")) return;
  const wrapper = link.closest(".table-wrapper");
  const box = wrapper.getBoundingClientRect();
  const left = box.left + wrapper.clientLeft;
  const right = left + wrapper.clientWidth;
  const r = link.getBoundingClientRect();
  const pad = 4; // the focus ring's width plus its offset
  if (r.right + pad > right) {
    wrapper.scrollLeft += Math.min(r.right + pad - right, r.left - pad - left);
  } else if (r.left - pad < left) {
    wrapper.scrollLeft -= left - (r.left - pad);
  }
});
