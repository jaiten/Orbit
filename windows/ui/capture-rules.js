// Quick add rules (Settings → Quick add rules), synced as one preferences record like Day starts at.
//   places: [{ name, days }]  "@mums" puts a task on the next of those weekdays (0 = Sunday), today included.
//   progressWords: words that always turn on start & finish for a new task with one of them in its title.
// iPhone: ios/Shared/CaptureRules.swift.
const CAPTURE_RULES_ID = "00000000-0000-4000-8000-000000000003";
const DAY_NAMES = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
function captureRules() {
  const record = rows("preferences").find((p) => p.id === CAPTURE_RULES_ID) || {};
  return {
    places: Array.isArray(record.places) ? record.places.filter((p) => p?.name && Array.isArray(p.days)) : [],
    progressWords: Array.isArray(record.progressWords) ? record.progressWords.filter((w) => typeof w === "string") : [],
  };
}
function saveCaptureRules(change) {
  return put("preferences", { ...captureRules(), ...change, id: CAPTURE_RULES_ID, updatedAt: Date.now() });
}
/** "mums = Thu, Fri" per line → [{ name: "mums", days: [4, 5] }]. Also "weekdays", "weekends", "mon-wed". */
function parsePlaceLines(text) {
  const places = [];
  for (const line of String(text).split("\n")) {
    const match = line.match(/^\s*@?([\p{L}\p{N}_'-]+)\s*[=:]\s*(.+)$/u);
    if (!match) continue;
    const days = new Set();
    for (const part of match[2]
      .toLowerCase()
      .split(/[,\s]+|\band\b/)
      .filter(Boolean)) {
      if (part.startsWith("weekday")) [1, 2, 3, 4, 5].forEach((d) => days.add(d));
      else if (part.startsWith("weekend")) [0, 6].forEach((d) => days.add(d));
      else {
        const [from, to] = part.split("-").map((word) => DAY_NAMES.indexOf(word.slice(0, 3)));
        if (from < 0) continue;
        if (to === undefined || to < 0) days.add(from);
        else for (let d = from; d !== (to + 1) % 7; d = (d + 1) % 7) days.add(d);
      }
    }
    if (days.size) places.push({ name: match[1].toLowerCase(), days: [...days].sort() });
  }
  return places;
}
const placeLines = (places) =>
  places
    .map((p) => `${p.name} = ${p.days.map((d) => DAY_NAMES[d][0].toUpperCase() + DAY_NAMES[d].slice(1)).join(", ")}`)
    .join("\n");
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
    <label class="settings-stack" for="place-rules"><span>Places, one per line. Type @name in a task to put it on the next of those days.</span>
      <textarea id="place-rules" rows="3" placeholder="mums = Mon, Tue, Wed&#10;dads = Thu-Sun" spellcheck="false">${esc(placeLines(rules.places))}</textarea></label>
    <label class="settings-stack" for="progress-rules"><span>Always track start &amp; finish for tasks with these words</span>
      <input id="progress-rules" placeholder="laundry, print, bake" spellcheck="false" value="${esc(rules.progressWords.join(", "))}" /></label>
    <p class="secondary">Orbit also learns: after you track start &amp; finish on a task, similar tasks suggest it, and from the second time on they start with it. Turn it off on one to teach it otherwise.</p>
  </section>${somedayRulesSection()}`;
}
function bindCaptureRules() {
  bindSomedayRules();
  const places = $("#place-rules"),
    words = $("#progress-rules");
  if (places)
    places.onchange = () => {
      const parsed = parsePlaceLines(places.value);
      void action(() => saveCaptureRules({ places: parsed }));
    };
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
    const sources = calendars.filter((calendar) => calendar.title === rule.calendar);
    if (sources.length !== 1) return false;
    const [source] = sources;
    const account = linked().accounts.find((item) => item.id === source.account);
    // A mirrored Apple calendar may be stale or only partially synced. Its absence proves nothing.
    if (rule.trigger === "noEvent" && (!account || account.error)) return false;
    if (account?.error) return false;
    const titles = events
      .filter(
        (event) =>
          event.calendarID === source.id &&
          (event.allDay
            ? event.startDay <= day && day < (event.endDay || OrbitCalendarEvents.addDays(event.startDay, 1))
            : event.start < next && (event.end || event.start + 1) > start),
      )
      .map((event) => event.title || "");
    return OrbitSomedayRules.matches(rule, day, titles);
  });
  return new Set(active.map((rule) => rule.tag));
}

function somedayRulesSection() {
  return `<section class="settings-block" id="someday-rules">
    <h2>Someday visibility rules</h2>
    <p class="secondary">Type a configured @tag in a task to keep it in Someday. Any matching rule can show it in Today.</p>
    <div id="someday-rule-rows"></div>
    <button type="button" id="someday-rule-add">Add rule</button>
    <button type="button" id="someday-rule-homes">Add Dad and Mum example</button>
    <button type="button" id="someday-rule-save">Save rules</button>
  </section>`;
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
             ${rule.trigger === "noEvent" ? '<p class="secondary">This rule needs a directly linked, available calendar on Windows.</p>' : ""}`
          : `<label>Start date<input name="start" type="date" value="${esc(rule.start)}"></label>
             ${
               rule.trigger === "dates"
                 ? `<label>End date (optional)<input name="end" type="date" value="${esc(rule.end)}"></label>`
                 : `<label>Every (in ${rule.trigger})<input name="interval" type="number" min="1" max="52" value="${rule.interval}"></label>`
             }`;
        return `<fieldset data-rule-index="${index}"><legend>Rule ${index + 1}</legend>
          <label>Tag<input name="tag" placeholder="dads" value="${esc(rule.tag)}" maxlength="40"></label>
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
  $("#someday-rule-homes").onclick = () => {
    draft.push(
      { ...empty(), tag: "dads", title: "Kidz @ James" },
      { ...empty(), tag: "mum", title: "Kidz @ James", trigger: "noEvent" },
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
      showNotice("Someday rules saved.");
    });
  renderRules();
}
