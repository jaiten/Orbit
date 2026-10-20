// Sync keeps both versions when two devices change the same thing; this page lets you choose.
function versionSummary(p, deleted) {
  if (deleted) return "Removed item";
  const repeat =
    { "FREQ=DAILY": "Daily", "FREQ=WEEKLY": "Weekly", "FREQ=MONTHLY": "Monthly" }[p.recurrenceRule] || "Custom";
  return [
    p.title || p.name || "Item",
    p.notes,
    p.localDate ? "Planned for " + p.localDate : "",
    p.count !== undefined ? p.count + " check-ins" : "",
    p.completedAt ? "Completed" : "",
    p.target ? `${OrbitHabits.label(p)}, ${p.target} ${p.frequencyRule === "WEEKLY" ? "a week" : "a day"}` : "",
    p.tags?.length ? "Tags: " + p.tags.join(", ") : "",
    p.priority ? "Priority: " + ["Normal", "Low", "Medium", "High"][p.priority] : "",
    p.recurrenceRule ? "Repeat: " + repeat : "",
    p.subtasks?.length ? "Steps: " + p.subtasks.map((s) => (s.completed ? "✓ " : "") + s.title).join(", ") : "",
  ]
    .filter(Boolean)
    .join("\n");
}

function renderReview() {
  const conflicts = state.records.filter((r) => r.conflict);
  if (!conflicts.length) return '<h1>Review</h1><p class="empty">Nothing to review.</p>';
  return (
    '<h1>Review</h1><p class="secondary">Sync kept two versions of these items. Choose the one to keep.</p>' +
    conflicts
      .map(
        (r) => `<section class="settings-block conflict">
          <div class="version-options">
            <div>
              <h3>On this PC</h3>
              <p class="version-text">${esc(versionSummary(r.payload, r.deleted))}</p>
              <button data-resolve="${esc(r.key)}" data-choice="local">Keep This Version</button>
            </div>
            <div>
              <h3>From sync</h3>
              <p class="version-text">${esc(versionSummary(r.conflict.payload, r.conflict.deleted))}</p>
              <button data-resolve="${esc(r.key)}" data-choice="cloud">Keep This Version</button>
            </div>
          </div>
        </section>`,
      )
      .join("")
  );
}

function bindReview() {
  document
    .querySelectorAll("[data-resolve]")
    .forEach((b) => (b.onclick = () => action(() => api.resolve(b.dataset.resolve, b.dataset.choice))));
  document.querySelectorAll("[data-review-conflicts]").forEach(
    (b) =>
      (b.onclick = () => {
        page = "review";
        render();
      }),
  );
}
