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
  </section>`;
}
function bindCaptureRules() {
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
