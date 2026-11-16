// Motion, the same physics as the website: springs from tokens.css (generated from
// shared/design-tokens.json), transform and opacity only. With reduced motion, movement becomes a fade.
const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
function spring() {
  return { easing: "cubic-bezier(0.2, 0.8, 0.2, 1)", duration: 160 };
}
const tokenNumber = (name, fallback) =>
  parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name)) || fallback;

// Lists re-form in one movement: rows slide inside their list, the list's edge follows them over the
// same time, and whatever sits below is carried along by the layout. Nothing flies across the page.
const FOLD = { duration: 240, easing: "cubic-bezier(0.2, 0.8, 0.2, 1)" };

/**
 * The list a row sits in, and a name for it that survives a re-render: its heading with the counts
 * taken out, so "3 completed" and "4 completed" are the same list.
 */
function rowGroup(row) {
  const list = row.closest("[data-flip-group], .check-list");
  if (!list) return null;
  if (list.dataset.flipGroup) return { list, key: list.dataset.flipGroup };
  const before = list.previousElementSibling;
  const label = before?.matches(".section-label, summary") ? before : list.closest("details")?.querySelector("summary");
  const text = (label?.querySelector("h2")?.textContent ?? label?.textContent ?? "").replace(/\d+/g, "#").trim();
  return { list, key: (list.closest("[data-today-panel]")?.dataset.todayPanel ?? "") + "|" + text };
}
/** Where every movable row is inside its list, and how tall each list is, before a re-render. */
function captureRows() {
  const rows = new Map(),
    groups = new Map();
  document.querySelectorAll("#content [data-flip]").forEach((el) => {
    const group = rowGroup(el),
      rect = el.getBoundingClientRect();
    if (group && !groups.has(group.key)) groups.set(group.key, group.list.getBoundingClientRect());
    const base = group ? group.list.getBoundingClientRect() : { left: 0, top: 0 };
    rows.set(el.dataset.flip, {
      group: group?.key ?? null,
      x: rect.left - base.left,
      y: rect.top - base.top,
      shown: rect.height > 0,
    });
  });
  return { rows, groups };
}
/**
 * After a re-render: rows that moved within their list slide from their old place; rows that are new
 * slide in; rows that came from another list (a task just completed) simply fade in where they now
 * belong. Each list grows or shrinks with its rows.
 */
function settleRows(before) {
  const reduce = reducedMotion(),
    { easing, duration } = spring("ui");
  const slide = tokenNumber("--row-slide", 20);
  const lists = new Map();
  document.querySelectorAll("#content [data-flip]").forEach((el) => {
    const group = rowGroup(el);
    if (group && !lists.has(group.key)) lists.set(group.key, group.list);
    const now = el.getBoundingClientRect();
    if (!now.height) return;
    const old = before.rows.get(el.dataset.flip);
    if (!old?.shown) {
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
    if (old.group !== (group?.key ?? null)) {
      el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: reduce ? 200 : FOLD.duration, easing: "ease-out" });
      return;
    }
    const base = group ? group.list.getBoundingClientRect() : { left: 0, top: 0 };
    const dx = old.x - (now.left - base.left),
      dy = old.y - (now.top - base.top);
    if (reduce || (Math.abs(dx) < 1 && Math.abs(dy) < 1)) return;
    el.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "none" }], FOLD);
  });
  if (reduce) return;
  lists.forEach((list, key) => {
    const old = before.groups.get(key),
      now = list.getBoundingClientRect();
    if (!now.height || Math.abs((old?.height ?? 0) - now.height) < 1) return;
    // Rows still on their way are clipped at the edge, as if the card were closing over them.
    list.classList.add("folding");
    const frames = [{ height: (old?.height ?? 0) + "px" }, { height: now.height + "px" }];
    if (!old?.height) {
      frames[0].opacity = 0;
      frames[1].opacity = 1;
    }
    list
      .animate(frames, FOLD)
      .finished.catch(() => {})
      .then(() => list.classList.remove("folding"));
  });
}
/** Rows about to leave their list fade out first, so the rows around them never slide over their text. */
function fadeRows(rows) {
  return Promise.all(
    rows.map((row) =>
      row
        .animate([{ opacity: 1 }, { opacity: 0 }], { duration: 130, easing: "ease-out", fill: "forwards" })
        .finished.catch(() => {}),
    ),
  );
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
