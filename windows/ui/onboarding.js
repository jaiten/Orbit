// First launch: three short, skippable screens (capture, habits, sync) and optional examples.
// Content comes from shared/onboarding.json (onboarding-data.js), the same as iPhone.
const examples = OrbitOnboardingData.examples;
const exampleHabitIDs = new Set(examples.habits.map((h) => h.id));
const exampleKeys = new Set([
  ...examples.lists.map((l) => "lists/" + l.id),
  ...examples.tasks.map((t) => "tasks/" + t.id),
  ...examples.habits.map((h) => "habits/" + h.id),
]);
let onboardingStep = 0,
  chosenHabits = new Set();

function newHabit(fields, now = Date.now()) {
  return {
    id: crypto.randomUUID(),
    target: 1,
    icon: "leaf",
    reminderMinutes: null,
    nudgeMinutes: null,
    ...fields,
    createdAt: now,
    updatedAt: now,
  };
}

/** Example records with fixed IDs, dated today. Records that already exist (from another device) are left alone. */
function exampleChanges(now = new Date()) {
  const day = dayKey(now),
    stamp = now.getTime();
  const live = new Set(state.records.filter((r) => !r.deleted).map((r) => r.key));
  const lists = examples.lists.map((l, i) => ({
    key: "lists/" + l.id,
    payload: { id: l.id, name: l.name, color: l.color, sortOrder: rows("lists").length + i, updatedAt: stamp },
  }));
  const tasks = examples.tasks.map((e, i) => {
    const task = {
      ...newTask(e.title, e.someday ? null : day),
      id: e.id,
      listID: e.someday ? SOMEDAY : (e.list ?? null),
    };
    task.sortOrder = stamp + i;
    if (e.time != null) {
      const due = new Date(day + "T00:00:00");
      due.setHours(Math.floor(e.time / 60), e.time % 60, 0, 0);
      Object.assign(task, { hasTime: true, dueDate: due.getTime(), durationMinutes: e.minutes ?? 30 });
    }
    return task;
  });
  const habits = examples.habits.map((h) => ({ key: "habits/" + h.id, payload: { ...newHabit(h, stamp), id: h.id } }));
  return {
    tasks: tasks.filter((t) => !live.has("tasks/" + t.id)),
    extra: [...lists, ...habits].filter((c) => !live.has(c.key)),
  };
}
function hasExamples() {
  return state.records.some((r) => !r.deleted && exampleKeys.has(r.key));
}
/** Deletes the example records and their check-ins. The example list stays if you added your own tasks to it. */
function removeExamples() {
  const used = new Set(
    rows("tasks")
      .filter((t) => !exampleKeys.has("tasks/" + t.id))
      .map((t) => t.listID),
  );
  const changes = state.records
    .filter((r) => !r.deleted)
    .filter(
      (r) =>
        (exampleKeys.has(r.key) && !(r.key.startsWith("lists/") && used.has(r.payload.id))) ||
        (r.key.startsWith("habit_logs/") && exampleHabitIDs.has(r.payload.habitID)),
    )
    .map((r) => ({ key: r.key, payload: r.payload, deleted: true }));
  return api.batch(changes);
}

const onboardingDots = () =>
  `<div class="onboarding-dots" aria-hidden="true">${[0, 1, 2].map((i) => `<span class="${i === onboardingStep ? "on" : ""}"></span>`).join("")}</div>`;
const onboardingScreens = [
  () => `<h2>Welcome to Orbit</h2>
    <p class="secondary">Type anything. Orbit works out when.</p>
    <form id="onboarding-capture">
      <input name="text" aria-label="Quick add" placeholder="Try “gym tomorrow 6pm” or “read every day”" maxlength="500" autocomplete="off" />
      <p id="onboarding-preview" class="chip" aria-live="polite" hidden></p>
      <footer>
        <button type="button" id="onboarding-examples">Start with Examples</button
        ><button type="button" data-onboarding-next>Skip</button><button class="primary" type="submit">Add</button>
      </footer>
    </form>`,
  () => `<h2>Pick a habit or two</h2>
    <p class="secondary">Habits repeat on their own and reset at midnight.</p>
    <div class="habit-suggestions">${OrbitOnboardingData.habitSuggestions
      .map((s, i) => {
        const label =
          s.frequencyRule === "WEEKLY"
            ? `${s.target} times a week`
            : s.target > 1
              ? `${s.target} times a day`
              : OrbitHabits.label(s);
        return `<button type="button" data-suggestion="${i}" aria-pressed="${chosenHabits.has(i)}">${esc(s.title)}<small>${esc(label)}</small></button>`;
      })
      .join("")}</div>
    <footer><button type="button" data-onboarding-next>Skip</button><button class="primary" id="add-habits">Continue</button></footer>`,
  () => `<h2>Stay in sync</h2>
    <p class="secondary">Sign in to keep your iPhone and this PC in step. Everything stays on this PC until you do.</p>
    <footer><button type="button" data-onboarding-next>Not Now</button><button class="primary" id="onboarding-sync">Set Up Sync</button></footer>`,
];

function showOnboarding() {
  onboardingStep = 0;
  chosenHabits = new Set();
  renderOnboarding();
  $("#onboarding").showModal();
  $("#onboarding-capture")?.elements.text.focus();
}
function renderOnboarding() {
  $("#onboarding-step").innerHTML = onboardingScreens[onboardingStep]() + onboardingDots();
  bindOnboarding();
}
function nextOnboarding() {
  if (onboardingStep >= onboardingScreens.length - 1) return $("#onboarding").close();
  onboardingStep += 1;
  renderOnboarding();
  $("#onboarding-step").querySelector("input, .primary")?.focus();
}
function bindOnboarding() {
  document.querySelectorAll("[data-onboarding-next]").forEach((b) => (b.onclick = nextOnboarding));
  const form = $("#onboarding-capture");
  if (form) {
    const parse = () => OrbitPlanning.parse(form.elements.text.value, null);
    form.elements.text.oninput = () => {
      const text = OrbitPlanning.describe(parse());
      showChip($("#onboarding-preview"), text);
    };
    form.onsubmit = (e) => {
      e.preventDefault();
      const result = parse();
      if (!result.title) return nextOnboarding();
      quickContext = { defaultDate: null, listID: null };
      const records = quickRecords(result);
      void (records.habit ? api.batch(records.changes) : saveTasks([records.task], records.extra))
        .then(nextOnboarding)
        .catch((error) => showNotice(error.message));
    };
    $("#onboarding-examples").onclick = () => {
      const { tasks, extra } = exampleChanges();
      void saveTasks(tasks, extra)
        .then(nextOnboarding)
        .catch((error) => showNotice(error.message));
    };
  }
  document.querySelectorAll("[data-suggestion]").forEach(
    (b) =>
      (b.onclick = () => {
        const i = Number(b.dataset.suggestion);
        if (!chosenHabits.delete(i)) chosenHabits.add(i);
        b.setAttribute("aria-pressed", String(chosenHabits.has(i)));
      }),
  );
  if ($("#add-habits"))
    $("#add-habits").onclick = () => {
      const now = Date.now(),
        picked = [];
      const changes = [...chosenHabits].map((i) => {
        // Each new habit gets the next colour, counting the ones picked just before it.
        const habit = newHabit({ ...OrbitOnboardingData.habitSuggestions[i], color: nextHabitColor(picked) }, now + i);
        picked.push(habit.color);
        return { key: "habits/" + habit.id, payload: habit };
      });
      void (changes.length ? api.batch(changes) : Promise.resolve())
        .then(nextOnboarding)
        .catch((error) => showNotice(error.message));
    };
  if ($("#onboarding-sync"))
    $("#onboarding-sync").onclick = () => {
      page = "account";
      $("#onboarding").close();
    };
}
// Closing at any point (Escape, Not Now, Set Up Sync) finishes onboarding for good.
$("#onboarding").addEventListener("close", () => {
  void api.finishOnboarding();
  state.onboarded = true;
  void load(true);
});
