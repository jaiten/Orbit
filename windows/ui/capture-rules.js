// Quick add rules (Settings → Quick add rules), synced as one preferences record like Day starts at.
//   progressWords: words that always turn on start & finish for a new task with one of them in its title.
//   shortcuts: abbreviations quick add expands, [{ abbr, text }] (OrbitPlanning.expand).
// The same screen holds the Someday visibility rules (someday-rules.js), synced as their own record.
// iPhone: ios/Shared/CaptureRules.swift.
const CAPTURE_RULES_ID = "00000000-0000-4000-8000-000000000003";
function captureRules() {
  const record = rows("preferences").find((p) => p.id === CAPTURE_RULES_ID) || {};
  return {
    progressWords: Array.isArray(record.progressWords) ? record.progressWords.filter((w) => typeof w === "string") : [],
    shortcuts: Array.isArray(record.shortcuts)
      ? record.shortcuts.filter((s) => typeof s?.abbr === "string" && typeof s?.text === "string" && s.abbr && s.text)
      : [],
  };
}
/** "mtg = meeting with the team" per line (also -> or →) into [{ abbr, text }]; the last line for a word wins. */
function parseShortcuts(text) {
  const table = new Map();
  for (const line of String(text).split(/\r?\n/)) {
    const match = line.match(/^\s*(\S{1,24})\s*(?:=|->|→)\s*(.{1,200}?)\s*$/);
    if (match) table.set(match[1].toLowerCase(), { abbr: match[1].toLowerCase(), text: match[2] });
  }
  return [...table.values()];
}
const shortcutLines = (shortcuts) => shortcuts.map((s) => `${s.abbr} = ${s.text}`).join("\n");
/**
 * Expands an abbreviation as soon as its word is finished with a space, so you see the words that will be
 * saved. Ctrl+Z takes it back, like autocorrect.
 */
function attachShortcuts(field) {
  field.addEventListener("input", (event) => {
    if (event.inputType !== "insertText" || event.data !== " " || page === "lists") return;
    const caret = field.selectionStart;
    if (caret !== field.selectionEnd) return;
    const before = field.value.slice(0, caret - 1);
    const word = before.match(/(?:^|\s)(\S+)$/)?.[1];
    if (!word) return;
    const expanded = OrbitPlanning.expand(word, captureRules().shortcuts);
    if (expanded === word) return;
    field.setSelectionRange(caret - 1 - word.length, caret - 1);
    document.execCommand("insertText", false, expanded);
    const next = caret + expanded.length - word.length;
    field.setSelectionRange(next, next);
  });
}
function saveCaptureRules(change) {
  return put("preferences", { ...captureRules(), ...change, id: CAPTURE_RULES_ID, updatedAt: Date.now() });
}
/** Start & finish learned from earlier tasks (see OrbitPlanner.learnedProgress): null, "suggest" or "auto". */
function learnedProgress(title, exceptID = null) {
  const history = rows("tasks")
    .filter((t) => t.id !== exceptID && !t.isNote && (t.progressTracking === true || t.progressTracking === false))
    .map((t) => ({ title: t.title, tracking: t.progressTracking === true }));
  return OrbitPlanner.learnedProgress(title, history, captureRules().progressWords);
}
function captureRulesSection() {
  const rules = captureRules();
  return `<section class="settings-block" id="capture-rules"><h2>Quick add rules</h2>
    ${somedayRulesBlock()}
    <label class="settings-stack" for="progress-rules"><span>Always track start &amp; finish for tasks with these words</span>
      <input id="progress-rules" placeholder="laundry, print, bake" spellcheck="false" value="${esc(rules.progressWords.join(", "))}" /></label>
    <p class="secondary">Orbit also learns: after you track start &amp; finish on a task, similar tasks suggest it, and from the second time on they start with it. Turn it off on one to teach it otherwise.</p>
    <label class="settings-stack" for="capture-shortcuts"><span>Abbreviations</span>
      <textarea id="capture-shortcuts" rows="4" spellcheck="false" placeholder="mtg = meeting with the team&#10;gs = grocery shopping #errands&#10;standup = Standup weekdays 9:30am">${esc(shortcutLines(rules.shortcuts))}</textarea></label>
    <p class="secondary">One per line. In quick add, the word expands when you type a space after it, on this PC and your iPhone. The text can use quick add words like #category, a day or a time.</p>
  </section>`;
}
function bindCaptureRules() {
  bindSomedayRules();
  const shortcuts = $("#capture-shortcuts");
  if (shortcuts)
    shortcuts.onchange = () =>
      void action(async () => {
        const parsed = parseShortcuts(shortcuts.value);
        await saveCaptureRules({ shortcuts: parsed });
        shortcuts.value = shortcutLines(parsed);
        showNotice(`${parsed.length} ${parsed.length === 1 ? "abbreviation" : "abbreviations"} saved.`, {
          dismissAfter: 3000,
        });
      });
  const words = $("#progress-rules");
  if (words)
    words.onchange = () =>
      void action(() =>
        saveCaptureRules({
          progressWords: [
            ...new Set(
              words.value
                .split(",")
                .map((w) => w.trim().toLowerCase())
                .filter(Boolean),
            ),
          ],
        }),
      );
}

function somedayRules() {
  const record = rows("preferences").find((p) => p.id === OrbitSomedayRules.recordID);
  return Array.isArray(record?.rules) ? record.rules.filter(OrbitSomedayRules.valid) : [];
}

function visibilityCalendars() {
  return [...rows("calendars"), ...linked().calendars].filter((calendar) => calendar.shown !== false);
}

function activeSomedayTags(day) {
  const rules = somedayRules();
  const hasCalendarRule = rules.some((rule) => OrbitSomedayRules.usesCalendar(rule.trigger));
  const calendars = hasCalendarRule ? visibilityCalendars() : [];
  const events = calendars.length ? calendarEvents() : [];
  const start = +localDay(day);
  const next = +localDay(OrbitCalendarEvents.addDays(day, 1));
  const active = rules.filter((rule) => {
    if (!OrbitSomedayRules.usesCalendar(rule.trigger)) return OrbitSomedayRules.matches(rule, day);
    // The same calendar can arrive twice (shared from iPhone and linked here): read every copy.
    const sources = calendars.filter((calendar) => calendar.title === rule.calendar);
    if (!sources.length) return false;
    const accounts = sources.map((source) => linked().accounts.find((item) => item.id === source.account));
    // A linked calendar that loaded proves an absence. So does an iPhone calendar for a day inside the window of
    // events the iPhone says it shares (eventsFrom ≤ day < eventsThrough); outside it, absence proves nothing.
    const proves = (source, index) =>
      accounts[index]
        ? !accounts[index].error
        : !!source.eventsFrom && source.eventsFrom <= day && day < (source.eventsThrough || "");
    if (rule.trigger === "noEvent" && !sources.some(proves)) return false;
    if (rule.trigger === "event" && accounts.every((account) => account?.error)) return false;
    const ids = new Set(sources.map((source) => source.id));
    const titles = events
      .filter(
        (event) =>
          ids.has(event.calendarID) &&
          (event.allDay
            ? event.startDay <= day && day < (event.endDay || OrbitCalendarEvents.addDays(event.startDay, 1))
            : event.start < next && (event.end || event.start + 1) > start),
      )
      .map((event) => event.title || "");
    return OrbitSomedayRules.matches(rule, day, titles);
  });
  return new Set(active.map((rule) => rule.tag));
}

/**
 * Open Someday tasks whose @tag has a rule matching `day` (today or later), for Calendar and Coming up.
 * The returned function remembers each day's rules for one render.
 */
function somedayMatcher(tasks) {
  const tagged = somedayRules().length
    ? tasks.filter(
        (task) => task.listID === SOMEDAY && !task.completedAt && OrbitSomedayRules.tags(task.title || "").size,
      )
    : [];
  const cache = new Map();
  return (day) => {
    if (!tagged.length || day < today()) return [];
    if (!cache.has(day)) {
      const active = activeSomedayTags(day);
      cache.set(
        day,
        active.size ? tagged.filter((task) => OrbitSomedayRules.onToday(task, day, active, plannerDay)) : [],
      );
    }
    return cache.get(day);
  };
}

function somedayRulesBlock() {
  return `<div class="settings-stack" id="someday-rules">
    <span>Someday visibility rules</span>
    <p class="secondary">Type a configured @tag in a task to keep it in Someday. Any matching rule can show it in Today.</p>
    <div id="someday-rule-rows"></div>
    <div class="settings-actions">
      <button type="button" id="someday-rule-add">Add rule</button>
      <button type="button" id="someday-rule-example">Add office and home example</button>
      <button type="button" id="someday-rule-save">Save rules</button>
    </div>
  </div>`;
}

function bindSomedayRules() {
  const list = $("#someday-rule-rows");
  if (!list) return;
  let draft = somedayRules();
  const empty = () => ({
    id: crypto.randomUUID(),
    tag: "",
    trigger: "event",
    calendar: "",
    title: "",
    start: today(),
    end: "",
    interval: 1,
  });
  const option = (key, label, selection) =>
    `<option value="${esc(key)}" ${key === selection ? "selected" : ""}>${esc(label)}</option>`;
  const renderRules = () => {
    const available = visibilityCalendars()
      .map((calendar) => calendar.title)
      .filter(Boolean);
    list.innerHTML = draft
      .map((rule, index) => {
        const sources = [...new Set([...available, rule.calendar].filter(Boolean))].sort();
        const condition = OrbitSomedayRules.usesCalendar(rule.trigger)
          ? `<label>Calendar<select name="calendar">${option("", "Select a calendar", rule.calendar)}${sources.map((name) => option(name, name, rule.calendar)).join("")}</select></label>
             <label>Event title contains<input name="title" value="${esc(rule.title)}" maxlength="200"></label>
             ${rule.trigger === "noEvent" ? '<p class="secondary">Uses what your iPhone last shared, or a calendar linked on this PC.</p>' : ""}`
          : `<label>Start date<input name="start" type="date" value="${esc(rule.start)}"></label>
             ${
               rule.trigger === "dates"
                 ? `<label>End date (optional)<input name="end" type="date" data-placeholder="No end" value="${esc(rule.end)}"></label>`
                 : `<label>Every (in ${rule.trigger})<input name="interval" type="number" min="1" max="52" value="${rule.interval}"></label>`
             }`;
        return `<fieldset data-rule-index="${index}"><legend>Rule ${index + 1}</legend>
          <label>Tag<input name="tag" placeholder="office" value="${esc(rule.tag)}" maxlength="40"></label>
          <label>Show in Today when<select name="trigger">${Object.entries(OrbitSomedayRules.triggers)
            .map(([key, label]) => option(key, label, rule.trigger))
            .join("")}</select></label>
          ${condition}<button type="button" data-remove-rule>Remove rule</button></fieldset>`;
      })
      .join("");
  };
  list.oninput = (event) => {
    const field = event.target;
    const rule = draft[Number(field.closest("[data-rule-index]")?.dataset.ruleIndex)];
    if (rule && field.name in rule) rule[field.name] = field.name === "interval" ? field.valueAsNumber : field.value;
  };
  list.onchange = (event) => {
    if (event.target.name === "trigger") renderRules();
  };
  list.onclick = (event) => {
    const button = event.target.closest("[data-remove-rule]");
    if (!button) return;
    draft.splice(Number(button.closest("[data-rule-index]").dataset.ruleIndex), 1);
    renderRules();
  };
  $("#someday-rule-add").onclick = () => {
    draft.push(empty());
    renderRules();
  };
  $("#someday-rule-example").onclick = () => {
    draft.push(
      { ...empty(), tag: "office", title: "Office day" },
      { ...empty(), tag: "home", title: "Office day", trigger: "noEvent" },
    );
    renderRules();
  };
  $("#someday-rule-save").onclick = () =>
    void action(async () => {
      const rules = draft.map((rule) => ({ ...rule, tag: rule.tag.trim().replace(/^@/, "").toLowerCase() }));
      if (!rules.every(OrbitSomedayRules.valid))
        throw Error("Give each rule a valid tag and select a calendar or dates.");
      const id = OrbitSomedayRules.recordID;
      await put("preferences", { id, rules, updatedAt: Date.now() });
      // Tasks already tagged before the rule existed are still on their own day; offer to hand them to the rule.
      const ruled = new Set(rules.map((rule) => rule.tag));
      const tagged = rows("tasks").filter(
        (task) =>
          !task.isNote &&
          !task.completedAt &&
          task.listID !== SOMEDAY &&
          [...OrbitSomedayRules.tags(task.title || "")].some((tag) => ruled.has(tag)),
      );
      if (!tagged.length) return showNotice("Someday rules saved.", { dismissAfter: 4000 });
      showNotice(
        `Someday rules saved. ${tagged.length} open ${tagged.length === 1 ? "task already has" : "tasks already have"} a ruled tag.`,
        {
          action: {
            label: "Let the rules show them",
            run: () =>
              action(async () => {
                await saveTasks(tagged.map((task) => OrbitPlanner.moveToSomeday(task)));
                showNotice(`Moved ${tagged.length} to Someday. They show in Today when a rule matches.`, {
                  dismissAfter: 5000,
                });
              }),
          },
        },
      );
    });
  renderRules();
}
