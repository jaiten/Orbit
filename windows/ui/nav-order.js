// Sidebar page order, as iOS's Tab order: a device preference kept in localStorage. Ctrl+1… follow the
// order shown, so the top page is always Ctrl+1. Mirrors OrbitTab.ordered in
// ios/App/NavigationCustomization.swift ("lists" is Windows's Notes page).
const OrbitNavOrder = (() => {
  const DEFAULT = ["today", "calendar", "tasks", "lists", "habits"];
  /** Known pages from `saved` in that order, then any missing ones in default order. */
  function ordered(saved) {
    const result = [];
    for (const name of String(saved || "").split(",")) {
      if (DEFAULT.includes(name) && !result.includes(name)) result.push(name);
    }
    return result.concat(DEFAULT.filter((name) => !result.includes(name)));
  }
  /** `order` with `name` moved to `index`. */
  function move(order, name, index) {
    const rest = order.filter((item) => item !== name);
    rest.splice(Math.max(0, Math.min(index, rest.length)), 0, name);
    return rest;
  }
  return { DEFAULT, ordered, move };
})();
if (typeof module !== "undefined") module.exports = OrbitNavOrder;

const NAV_NAMES = { today: "Today", calendar: "Calendar", tasks: "Tasks", lists: "Notes", habits: "Habits" };
const navOrder = () => {
  try {
    return OrbitNavOrder.ordered(localStorage.getItem("tabOrder"));
  } catch {
    return [...OrbitNavOrder.DEFAULT];
  }
};
/** Saves the order and redraws the sidebar's buttons and their Ctrl+ labels. */
function saveNavOrder(order) {
  localStorage.setItem("tabOrder", order.join(","));
  applyNavOrder();
}
function applyNavOrder() {
  const nav = document.querySelector("nav[aria-label='Planner']");
  if (!nav) return;
  navOrder().forEach((name, index) => {
    const button = nav.querySelector(`button[data-page="${name}"]`);
    if (!button) return;
    nav.append(button);
    button.setAttribute("aria-keyshortcuts", `Control+${index + 1}`);
    const kbd = button.querySelector("kbd");
    if (kbd) kbd.textContent = `Ctrl+${index + 1}`;
  });
  if (typeof movePill === "function") movePill();
}
/** Drag a page in the sidebar to move it. */
function bindNavDrag() {
  const nav = document.querySelector("nav[aria-label='Planner']");
  if (!nav) return;
  nav.querySelectorAll("button[data-page]").forEach((button) => {
    button.draggable = true;
    button.ondragstart = (event) => {
      event.dataTransfer.setData("text/orbit-page", button.dataset.page);
      event.dataTransfer.effectAllowed = "move";
    };
    button.ondragover = (event) => {
      if (!event.dataTransfer.types.includes("text/orbit-page")) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = "move";
    };
    button.ondrop = (event) => {
      const source = event.dataTransfer.getData("text/orbit-page");
      if (!source || source === button.dataset.page) return;
      event.preventDefault();
      const order = navOrder();
      saveNavOrder(OrbitNavOrder.move(order, source, order.indexOf(button.dataset.page)));
    };
  });
}
