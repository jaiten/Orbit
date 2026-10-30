function bindTodayBoard() {
  const panels = [...document.querySelectorAll("[data-today-panel]")];
  if (!panels.length) return;
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
  const place = (placeholder, x, y) => {
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
    target.insertBefore(placeholder, before || null);
  };
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
      let finished = false;
      grip.onpointermove = (move) => {
        ghost.style.left = `${move.clientX - offsetX}px`;
        ghost.style.top = `${move.clientY - offsetY}px`;
        place(placeholder, move.clientX, move.clientY);
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
      main?.firstElementChild?.dataset.todayPanel === "tasks" &&
      side?.firstElementChild?.dataset.todayPanel === "recent"
    ) {
      const first = main.querySelector(".task-row, .empty-state");
      if (first && innerWidth > 1000)
        side.style.paddingTop = `${Math.max(0, first.getBoundingClientRect().top - main.getBoundingClientRect().top)}px`;
    }
  }
}
