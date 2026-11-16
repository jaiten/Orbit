let todayBoardObserver;
function bindTodayBoard() {
  todayBoardObserver?.disconnect();
  const panels = [...document.querySelectorAll("[data-today-panel]")];
  if (!panels.length) return;
  const board = document.querySelector(".today-board");
  const divider = document.querySelector("#today-column-resizer");
  const storedShare = Number(localStorage.getItem("todayColumnShare"));
  const applyShare = (share, save = false) => {
    const value = Math.max(35, Math.min(75, share));
    board.style.gridTemplateColumns = `${value}fr ${100 - value}fr`;
    divider?.setAttribute("aria-valuenow", String(Math.round(value)));
    if (save) localStorage.setItem("todayColumnShare", String(value));
    return value;
  };
  if (storedShare >= 35 && storedShare <= 75) applyShare(storedShare);
  if (divider) {
    const main = board.querySelector('[data-panel-drop="main"]');
    const align = () => {
      divider.style.left = `${main.getBoundingClientRect().right - board.getBoundingClientRect().left + 6}px`;
      divider.setAttribute("aria-valuenow", String(Math.round((main.clientWidth / (board.clientWidth - 24)) * 100)));
    };
    todayBoardObserver = new ResizeObserver(align);
    todayBoardObserver.observe(board);
    align();
    divider.onkeydown = (event) => {
      if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      event.stopPropagation();
      applyShare(
        event.key === "Home"
          ? 35
          : event.key === "End"
            ? 75
            : Number(divider.getAttribute("aria-valuenow")) + (event.key === "ArrowRight" ? 2 : -2),
        true,
      );
      align();
    };
    divider.onpointerdown = (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      const original = board.style.gridTemplateColumns;
      let share = Number(divider.getAttribute("aria-valuenow"));
      divider.setPointerCapture(event.pointerId);
      divider.onpointermove = (move) => {
        share = applyShare(((move.clientX - board.getBoundingClientRect().left - 12) / (board.clientWidth - 24)) * 100);
        align();
      };
      const finish = (cancel) => {
        divider.onpointermove = divider.onpointerup = divider.onpointercancel = divider.onlostpointercapture = null;
        if (cancel) board.style.gridTemplateColumns = original;
        else applyShare(share, true);
        align();
      };
      divider.onpointerup = () => finish(false);
      divider.onpointercancel = divider.onlostpointercapture = () => finish(true);
    };
  }
  const layout = JSON.parse(localStorage.getItem("todayPanelLayout") || "{}");
  const fallback = new Map(panels.map((panel, index) => [panel, index]));
  panels.sort(
    (a, b) =>
      (layout[a.dataset.todayPanel]?.order ?? fallback.get(a)) -
      (layout[b.dataset.todayPanel]?.order ?? fallback.get(b)),
  );
  panels.forEach((panel) => document.querySelector(`[data-panel-drop="${panel.dataset.panelColumn}"]`)?.append(panel));
  const persist = () => {
    const values = {};
    document.querySelectorAll("[data-panel-drop]").forEach((column) =>
      [...column.children]
        .filter((panel) => panel.dataset.todayPanel)
        .forEach((panel, order) => {
          values[panel.dataset.todayPanel] = { column: column.dataset.panelDrop, order };
        }),
    );
    localStorage.setItem("todayPanelLayout", JSON.stringify(values));
    render();
  };
  const place = (placeholder, x, y, settled = false) => {
    const columns = [...document.querySelectorAll("[data-panel-drop]")];
    const target =
      document.elementFromPoint(x, y)?.closest("[data-panel-drop]") ||
      columns.reduce(
        (best, column) =>
          Math.abs(column.getBoundingClientRect().left + column.clientWidth / 2 - x) <
          Math.abs(best.getBoundingClientRect().left + best.clientWidth / 2 - x)
            ? column
            : best,
        columns[0],
      );
    const candidates = [...target.children].filter(
      (panel) => panel.dataset.todayPanel && !panel.hidden && !panel.classList.contains("drag-source"),
    );
    const before = candidates.find(
      (panel) => y < panel.getBoundingClientRect().top + panel.getBoundingClientRect().height / 2,
    );
    // The gap is already there, or the panels are still sliding from the last change.
    const shown = (panel) => panel.dataset.todayPanel && !panel.hidden && !panel.classList.contains("drag-source");
    let next = placeholder.nextElementSibling;
    while (next && !shown(next)) next = next.nextElementSibling;
    if (placeholder.parentElement === target && next === (before || null)) return;
    // (When the panel is let go, the gap goes straight to where the pointer is.)
    if (!settled && performance.now() - lastPlaced < 170) return;
    lastPlaced = performance.now();
    // The other panels slide out of the way rather than jumping.
    const others = panels.filter(shown);
    const from = new Map(others.map((panel) => [panel, panel.getBoundingClientRect()]));
    target.insertBefore(placeholder, before || null);
    if (settled || reducedMotion()) return;
    others.forEach((panel) => {
      const old = from.get(panel),
        now = panel.getBoundingClientRect();
      const dx = old.left - now.left,
        dy = old.top - now.top;
      if (Math.abs(dx) < 1 && Math.abs(dy) < 1) return;
      panel.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "none" }], {
        duration: 170,
        easing: "cubic-bezier(0.2, 0.8, 0.2, 1)",
      });
    });
  };
  let lastPlaced = 0;
  panels.forEach((panel) => {
    panel.ondragstart = (event) => {
      if (!editingTodayLayout) {
        event.preventDefault();
        return;
      }
      event.dataTransfer.setData("text/orbit-panel", panel.dataset.todayPanel);
    };
    const grip = panel.querySelector("[data-move-panel]");
    if (!grip) return;
    grip.onpointerdown = (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      event.stopPropagation();
      const originalParent = panel.parentElement,
        originalNext = panel.nextSibling;
      const box = panel.getBoundingClientRect();
      const placeholder = document.createElement("div");
      placeholder.className = "layout-placeholder";
      placeholder.style.height = `${Math.max(70, box.height)}px`;
      panel.before(placeholder);
      const ghost = panel.cloneNode(true);
      ghost.classList.add("layout-ghost");
      ghost.style.width = `${box.width}px`;
      ghost.style.left = `${box.left}px`;
      ghost.style.top = `${box.top}px`;
      ghost.removeAttribute("draggable");
      document.body.append(ghost);
      panel.classList.add("drag-source");
      grip.setPointerCapture(event.pointerId);
      const offsetX = event.clientX - box.left,
        offsetY = event.clientY - box.top;
      let finished = false,
        last = null;
      grip.onpointermove = (move) => {
        last = move;
        place(placeholder, move.clientX, move.clientY);
        ghost.style.width = `${placeholder.getBoundingClientRect().width}px`;
        ghost.style.left = `${move.clientX - Math.min(offsetX, ghost.clientWidth - 20)}px`;
        ghost.style.top = `${move.clientY - offsetY}px`;
        if (move.clientY < 80) window.scrollBy(0, -18);
        else if (move.clientY > innerHeight - 80) window.scrollBy(0, 18);
      };
      const onCancelKey = (key) => {
        if (key.key === "Escape") {
          key.preventDefault();
          key.stopPropagation();
          finish(true);
        }
      };
      const onBlur = () => finish(true);
      window.addEventListener("keydown", onCancelKey, true);
      window.addEventListener("blur", onBlur);
      const finish = (cancel) => {
        if (finished) return;
        finished = true;
        window.removeEventListener("keydown", onCancelKey, true);
        window.removeEventListener("blur", onBlur);
        grip.onlostpointercapture = null;
        grip.onpointermove = null;
        grip.onpointerup = null;
        grip.onpointercancel = null;
        const settle = () => {
          ghost.remove();
          panel.classList.remove("drag-source");
          if (cancel) {
            originalParent.insertBefore(panel, originalNext?.isConnected ? originalNext : null);
            placeholder.remove();
          } else {
            placeholder.replaceWith(panel);
            persist();
          }
        };
        if (!cancel && last) place(placeholder, last.clientX, last.clientY, true);
        if (cancel || reducedMotion() || !placeholder.isConnected) return settle();
        // Let go: the panel glides into the gap it was dropped on.
        const land = placeholder.getBoundingClientRect();
        ghost
          .animate([{}, { left: `${land.left}px`, top: `${land.top}px`, rotate: "0deg" }], {
            duration: 150,
            easing: "cubic-bezier(0.2, 0.8, 0.2, 1)",
            fill: "forwards",
          })
          .finished.catch(() => {})
          .then(settle);
      };
      grip.onpointerup = () => finish(false);
      grip.onpointercancel = () => finish(true);
      grip.onlostpointercapture = () => finish(true);
    };
    grip.onkeydown = (event) => {
      if (!["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(event.key)) return;
      event.preventDefault();
      event.stopPropagation();
      if (event.key === "ArrowUp" && panel.previousElementSibling) panel.previousElementSibling.before(panel);
      if (event.key === "ArrowDown" && panel.nextElementSibling) panel.nextElementSibling.after(panel);
      if (["ArrowLeft", "ArrowRight"].includes(event.key)) {
        const column = document.querySelector(`[data-panel-drop="${event.key === "ArrowLeft" ? "main" : "side"}"]`);
        column.append(panel);
      }
      const id = panel.dataset.todayPanel;
      persist();
      document.querySelector(`[data-move-panel="${id}"]`)?.focus();
    };
  });
  document.querySelectorAll("[data-panel-drop]").forEach((column) => {
    column.ondragover = (event) => {
      if (editingTodayLayout && event.dataTransfer.types.includes("text/orbit-panel")) event.preventDefault();
    };
    column.ondrop = (event) => {
      if (!editingTodayLayout) return;
      const source = panels.find(
        (panel) => panel.dataset.todayPanel === event.dataTransfer.getData("text/orbit-panel"),
      );
      if (!source) return;
      event.preventDefault();
      const marker = document.createElement("div");
      source.classList.add("drag-source");
      place(marker, event.clientX, event.clientY);
      source.classList.remove("drag-source");
      marker.replaceWith(source);
      persist();
    };
  });
  if (!editingTodayLayout) {
    const main = document.querySelector('[data-panel-drop="main"]'),
      side = document.querySelector('[data-panel-drop="side"]');
    if (
      [...(main?.children || [])].find((panel) => !panel.hidden)?.dataset.todayPanel === "tasks" &&
      [...(side?.children || [])].find((panel) => !panel.hidden)?.dataset.todayPanel === "recent"
    ) {
      const first = main.querySelector(".task-row, .empty-state");
      if (first && innerWidth > 1000)
        side.style.paddingTop = `${Math.max(0, first.getBoundingClientRect().top - main.getBoundingClientRect().top)}px`;
    }
  }
}
