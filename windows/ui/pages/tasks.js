// A permanent home for dated, undated and Someday tasks.
let taskScope = "all",
  taskSort = "date",
  taskSearch = "";
function renderTasks(tasks) {
  const current = today(),
    week = OrbitHabits.weekStartKey(current, weekStart),
    end = OrbitHabits.addDays(week, 7);
  const filtered = tasks.filter((task) => {
    const date = taskDate(task);
    return (
      (!selectedList || task.listID === selectedList) &&
      `${task.title} ${task.notes || ""}`.toLowerCase().includes(taskSearch.toLowerCase()) &&
      (taskScope === "all" ||
        (taskScope === "today" && date === current && task.listID !== SOMEDAY) ||
        (taskScope === "week" && date >= week && date < end && task.listID !== SOMEDAY) ||
        (taskScope === "future" && date > current && task.listID !== SOMEDAY && !task.completedAt) ||
        (taskScope === "someday" && (!date || task.listID === SOMEDAY)))
    );
  });
  filtered.sort(
    (a, b) =>
      !!a.completedAt - !!b.completedAt ||
      (taskSort === "title"
        ? a.title.localeCompare(b.title)
        : taskSort === "manual"
          ? (a.sortOrder || 0) - (b.sortOrder || 0)
          : (taskDate(a) || "9999").localeCompare(taskDate(b) || "9999")),
  );
  const groups = ["Today", "Overdue", "Upcoming", "Someday", "Completed"]
    .map((group) => {
      const items = filtered.filter((task) => OrbitPlanner.dateGroup(planItem(task), current) === group);
      return !items.length
        ? ""
        : group === "Completed"
          ? `<details class="completed-tasks"><summary>Completed (${items.length})</summary>${checklist(items)}</details>`
          : sectionLabel(group, String(items.length)) + checklist(items);
    })
    .join("");
  return `<div class="narrow wide"><header class="page-head"><h1>Tasks</h1><input id="task-search" type="search" aria-label="Search tasks" placeholder="Search tasks" value="${esc(taskSearch)}" /></header>
    <div class="tasks-controls">${macPicker(
      "task-scope",
      "Show tasks",
      [
        ["all", "All tasks"],
        ["today", "Today"],
        ["week", "This week"],
        ["future", "Future"],
        ["someday", "Someday"],
      ],
      taskScope,
    )}
    ${macPicker("task-category", "Task category", [["", "All categories"], ...orderedLists().map((list) => [list.id, list.name]), [SOMEDAY, "Someday"]], selectedList || "")}
    ${macPicker(
      "task-sort",
      "Sort tasks",
      [
        ["date", "By date"],
        ["title", "By title"],
        ["manual", "As arranged"],
      ],
      taskSort,
    )}<button class="quiet-control" data-new-list>New category</button></div>
    ${groups || '<p class="empty">No tasks in this view.</p>'}<div class="capture-dock">${addField()}</div></div>`;
}
function bindTasks() {
  if (!$("#task-scope")) return;
  bindPickers({
    "task-scope": (value) => {
      taskScope = value;
      render();
    },
    "task-category": (value) => {
      selectedList = value || null;
      render();
    },
    "task-sort": (value) => {
      taskSort = value;
      render();
    },
  });
  $("#task-search").oninput = (e) => {
    taskSearch = e.target.value;
    const start = e.target.selectionStart,
      end = e.target.selectionEnd;
    render();
    $("#task-search").focus();
    $("#task-search").setSelectionRange(start, end);
  };
}
