// Motion, the same physics as the website: springs from tokens.css (generated from
// shared/design-tokens.json), transform and opacity only. With reduced motion, movement becomes a fade.
const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
function spring() {
  return { easing: "cubic-bezier(0.2, 0.8, 0.2, 1)", duration: 160 };
}
const tokenNumber = (name, fallback) =>
  parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name)) || fallback;

/** Where every movable row is, keyed by data-flip, before a re-render. */
function captureRows() {
  const rects = new Map();
  document
    .querySelectorAll("#content [data-flip]")
    .forEach((el) => rects.set(el.dataset.flip, el.getBoundingClientRect()));
  return rects;
}
/** After a re-render: rows that moved spring from their old place; new rows fade and slide in. */
function settleRows(before) {
  const reduce = reducedMotion(),
    { easing, duration } = spring("ui");
  const slide = tokenNumber("--row-slide", 20);
  document.querySelectorAll("#content [data-flip]").forEach((el) => {
    const old = before.get(el.dataset.flip);
    if (!old) {
      el.animate(
        reduce
          ? [{ opacity: 0 }, { opacity: 1 }]
          : [
              { opacity: 0, transform: `translateX(${-slide}px)` },
              { opacity: 1, transform: "none" },
            ],
        { duration: reduce ? 200 : duration, easing: reduce ? "ease-out" : easing },
      );
      return;
    }
    const now = el.getBoundingClientRect();
    const dx = old.left - now.left,
      dy = old.top - now.top;
    if (reduce || (Math.abs(dx) < 1 && Math.abs(dy) < 1)) return;
    el.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "none" }], { duration, easing });
  });
}
/**
 * A new page: one quick, soft cross-fade with a hint of focus, like switching panes on macOS. No row
 * stagger, so switching tabs never feels slow; rows only move when they actually change (settleRows).
 */
function enterPage() {
  const content = $("#content");
  content.getAnimations().forEach((a) => a.cancel());
  content.animate([{ opacity: 0.6 }, { opacity: 1 }], { duration: reducedMotion() ? 0 : 140, easing: "ease-out" });
}
/** A row leaving (an overdue item moved to Later or Someday). Resolves when it has gone. */
function leave(row) {
  const reduce = reducedMotion(),
    { easing, duration } = spring("ui");
  const keyframes = reduce
    ? [{ opacity: 1 }, { opacity: 0 }]
    : [
        { opacity: 1, transform: "none" },
        { opacity: 0, transform: "translateX(24px)" },
      ];
  return row
    .animate(keyframes, { duration: reduce ? 150 : Math.min(duration, 320), easing, fill: "forwards" })
    .finished.catch(() => {});
}

let planFill = null;
/** Applies data-driven values the CSP won't allow inline: grid opacities and the plan bar, which springs. */
function applyFills() {
  document
    .querySelectorAll("#content .box-grid i[data-o]")
    .forEach((cell) => cell.style.setProperty("--o", cell.dataset.o));
  document
    .querySelectorAll("#content .mini-bar i[data-fill]")
    .forEach((bar) => (bar.style.transform = `scaleX(${Number(bar.dataset.fill) || 0})`));
  const bar = $("#content .plan-bar i");
  if (!bar) return;
  const target = Number(bar.dataset.fill) || 0;
  const from = planFill ?? target;
  planFill = target;
  bar.style.transform = `scaleX(${target})`;
  if (from !== target && !reducedMotion()) {
    const { easing, duration } = spring("soft");
    bar.animate([{ transform: `scaleX(${from})` }, { transform: `scaleX(${target})` }], { duration, easing });
  }
}

let pillPlaced = false;
/** The sidebar's white pill slides to the selected page. */
function movePill() {
  const pill = $(".nav-pill"),
    active = $("nav button.selected");
  if (!pill) return;
  pill.hidden = !active;
  if (!active) return;
  const to = `translateY(${active.offsetTop}px)`;
  const from = pill.style.transform;
  pill.style.height = active.offsetHeight + "px";
  pill.style.transform = to;
  if (pillPlaced && from && from !== to && !reducedMotion()) {
    const { easing, duration } = spring("ui");
    pill.animate([{ transform: from }, { transform: to }], { duration, easing });
  }
  pillPlaced = true;
}
