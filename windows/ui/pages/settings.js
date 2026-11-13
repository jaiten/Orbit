// Settings: appearance, accent, reminders and your data. Account has its own page.
const appearances = ["system", "light", "dark"];
function applyAppearance(name) {
  if (!appearances.includes(name)) name = "system";
  document.documentElement.dataset.appearance = name;
  try {
    localStorage.setItem("appearance", name);
  } catch {
    /* Storage can be unavailable; the choice still applies for this session. */
  }
  void window.orbit?.setAppearance?.(name)?.catch?.(() => {});
}
// On Windows 11 the sidebar shows the window's Mica material (see polish.css).
if (window.orbit?.mica) document.documentElement.dataset.mica = "";
applyAppearance(localStorage.getItem("appearance") || "system");

function choiceButtons(attribute, values, current) {
  return values
    .map(
      (name) =>
        `<button data-${attribute}="${name}" aria-pressed="${current === name}">${name[0].toUpperCase() + name.slice(1)}</button>`,
    )
    .join("");
}

function applyCompact(value) {
  document.documentElement.dataset.compact = String(value);
  localStorage.setItem("compactRows", String(value));
}
applyCompact(localStorage.getItem("compactRows") === "true");

/** Calendars shared from Orbit on iPhone. Turning one off hides it here and on the iPhone. */
function calendarList() {
  const calendars = rows("calendars").sort(
    (a, b) =>
      String(a.account || "").localeCompare(String(b.account || "")) || String(a.title).localeCompare(String(b.title)),
  );
  if (!calendars.length)
    return `<h3>Calendars</h3><p class="secondary">Your calendars come from Orbit on iPhone. Open Settings → Calendars there, connect your calendars, and they'll appear here after the iPhone syncs.</p>`;
  return `<h3>Calendars</h3><p class="secondary">Shared from your iPhone. Turn a calendar off to hide it in Orbit on both devices; turn it back on to add it again. Edits you make here reach the calendar the next time Orbit syncs on your iPhone.</p>
    <div class="calendar-toggles">${calendars
      .map(
        (calendar) =>
          `<label class="toggle calendar-toggle" data-event-color="${/^#[0-9a-f]{6}$/i.test(calendar.color || "") ? calendar.color : "var(--muted)"}"><input type="checkbox" data-calendar-shown="${esc(calendar.id)}" ${calendar.shown === false ? "" : "checked"} /><span class="calendar-name"><i></i><span>${esc(calendar.title)}${calendar.account ? `<small>${esc(calendar.account)}</small>` : ""}</span></span></label>`,
      )
      .join("")}</div>`;
}

function renderSettings() {
  const root = document.documentElement.dataset;
  return `<header class="page-head"><div><div class="eyebrow">Preferences</div><h1>Settings</h1></div></header>
    <button class="card account-row" data-open-page="account"><span>Account</span><span class="${state.email ? "secondary" : "account-sign-in"}">${esc(state.email || "Sign in")}</span></button>
    <section class="settings-block">
      <h2>Appearance</h2>
      <label class="toggle"><input type="checkbox" id="compact-rows" ${root.compact === "true" ? "checked" : ""} /> Compact habits and tasks</label>
      <div class="accent-options segmented" role="group" aria-label="Appearance">${choiceButtons("appearance", appearances, root.appearance)}</div>
      <h3>Accent</h3><div class="accent-options segmented" role="group" aria-label="Accent">${choiceButtons("accent", accents, root.accent)}</div>
    </section>
    <section class="settings-block" id="sidebar-order"><h2>Sidebar order</h2>
      <ol class="nav-order-list">${navOrder()
        .map(
          (name, index, all) =>
            `<li><span>${NAV_NAMES[name]}</span><kbd>Ctrl+${index + 1}</kbd><button class="icon-button small" data-nav-move="${name}" data-step="-1" aria-label="Move ${NAV_NAMES[name]} up" ${index === 0 ? "disabled" : ""}>↑</button><button class="icon-button small" data-nav-move="${name}" data-step="1" aria-label="Move ${NAV_NAMES[name]} down" ${index === all.length - 1 ? "disabled" : ""}>↓</button></li>`,
        )
        .join("")}</ol>
      <p class="secondary">You can also drag pages in the sidebar. Ctrl+1… follow this order.</p>
      <button id="restore-nav-order" ${localStorage.getItem("tabOrder") ? "" : "disabled"}>Restore default order</button>
    </section>
    <section class="settings-block" id="today-preferences"><h2>Today & Progress</h2>
      <div class="settings-field"><span>Day starts at</span>${macPicker(
        "day-start",
        "Day starts at",
        OrbitPlanner.DAY_START_CHOICES.map((minutes) => [String(minutes), OrbitPlanner.dayStartLabel(minutes)]),
        String(dayStart()),
      )}</div>
      <p class="secondary">Until then, check-ins and finished tasks count for the day before. Syncs to your other devices.</p>
      <label class="toggle"><input type="checkbox" id="progress-tasks" ${localStorage.getItem("progressIncludesTasks") !== "false" ? "checked" : ""} /> Include tasks in daily progress</label>
      <div class="settings-field"><span>Overall progress</span>${macPicker(
        "overall-range",
        "Overall progress range",
        [
          ["7", "Past week"],
          ["30", "Past month"],
        ],
        localStorage.getItem("overallProgressRange") === "7" ? "7" : "30",
      )}</div>
      <p class="secondary">Recent progress always shows the last seven days; review earlier days in Calendar. Use the layout icon on Today to arrange or hide panels.</p>
    </section>
    <section class="settings-block" id="calendar-preferences"><h2>Calendar</h2>
      <div class="settings-field"><span>Clock format</span>${macPicker(
        "calendar-clock",
        "Calendar clock format",
        [
          ["12", "12 hour (AM / PM)"],
          ["24", "24 hour"],
        ],
        localStorage.getItem("calendarClock") === "24" ? "24" : "12",
      )}</div>
      <p class="secondary">The Any time row grows to fit the day with the most untimed tasks and all-day events.</p>
      ${calendarList()}
    </section>
    <section class="settings-block" id="desktop-settings">
      <h2>Notifications & Keyboard</h2>
      <label class="toggle"><input type="checkbox" id="notifications-toggle" /> Show reminders for tasks and habits</label>
      <div class="settings-field"><span>Quick add from anywhere</span><div id="global-shortcut-wrap"></div></div>
      <button id="show-shortcuts">Keyboard Shortcuts</button>
    </section>
    <section class="settings-block" id="writing-settings">
      <h2>Notes & Writing</h2>
      <label class="toggle"><input type="checkbox" id="autocorrect-toggle" ${OrbitAutocorrect.settings().enabled ? "checked" : ""} /> Correct as you type</label>
      <label class="toggle"><input type="checkbox" id="autocorrect-apostrophes" ${OrbitAutocorrect.settings().apostrophes ? "checked" : ""} /> Add apostrophes (dont → don't, im → I'm)</label>
      <label class="toggle"><input type="checkbox" id="autocorrect-spelling" ${OrbitAutocorrect.settings().spelling ? "checked" : ""} /> Fix one-letter typos the spell checker is sure about</label>
      <label class="settings-stack" for="autocorrect-rules"><span>Your rules, one per line</span>
        <textarea id="autocorrect-rules" rows="3" placeholder="btw = by the way" spellcheck="false">${esc(OrbitAutocorrect.customText())}</textarea></label>
      <p class="secondary">Ctrl+Z right after a correction takes it back.</p>
      <button id="notes-password">${OrbitLocks.hasPassword() ? "Change Notes Password" : "Set Notes Password"}</button>
      <p class="secondary">One password unlocks locked notes and sections on this PC. Right-click a note or section to lock it.</p>
    </section>
    <section class="settings-block">
      <h2>Data & Backup</h2>
      <button id="export-backup">Export Everything (JSON)</button><button id="export-csv">Export Tasks (CSV)</button
      ><button id="import-backup">Import…</button>
      <p class="secondary">The JSON file holds your tasks, lists and habit history and can be imported on iPhone or Windows. No account details are included.</p>
      <div id="import-confirm"></div>
    </section>
    ${
      hasExamples()
        ? `<section class="settings-block">
      <h2>Examples</h2>
      <button id="remove-examples">Remove Examples</button>
      <p class="secondary">Removes the example tasks, list and habits. Anything you added stays.</p>
    </section>`
        : ""
    }
    <section class="settings-block">
      <h2>Updates</h2>
      <p id="update-status" class="secondary" role="status"></p>
      <button id="check-updates">Check for updates</button><button id="install-update" hidden>Restart to update</button>
    </section>
    <p class="secondary app-version">Orbit ${esc(state.version || "")} for Windows</p>
  `;
}

function bindSettings() {
  if ($("#overall-range"))
    bindPickers(
      {
        "overall-range": (value) => {
          localStorage.setItem("overallProgressRange", value);
          render();
        },
        "day-start": (value) =>
          action(() =>
            put("preferences", {
              ...(rows("preferences").find((p) => p.id === OrbitPlanner.PREFERENCES_ID) || {}),
              id: OrbitPlanner.PREFERENCES_ID,
              dayStartMinutes: Number(value),
              updatedAt: Date.now(),
            }),
          ),
      },
      $("#today-preferences"),
    );
  if ($("#progress-tasks"))
    $("#progress-tasks").onchange = (event) =>
      localStorage.setItem("progressIncludesTasks", String(event.target.checked));
  if ($("#calendar-clock"))
    bindPickers(
      {
        "calendar-clock": (value) => {
          localStorage.setItem("calendarClock", value);
          render();
        },
      },
      $("#calendar-preferences"),
    );
  applyCalendarStyles($("#calendar-preferences") || document);
  document.querySelectorAll("[data-calendar-shown]").forEach((box) => {
    box.onchange = () => {
      const calendar = rows("calendars").find((item) => item.id === box.dataset.calendarShown);
      if (calendar) void action(() => put("calendars", { ...calendar, shown: box.checked, shownAt: Date.now() }));
    };
  });
  document.querySelectorAll("[data-nav-move]").forEach(
    (b) =>
      (b.onclick = () => {
        const order = navOrder();
        saveNavOrder(
          OrbitNavOrder.move(order, b.dataset.navMove, order.indexOf(b.dataset.navMove) + Number(b.dataset.step)),
        );
        render();
        $(`[data-nav-move="${b.dataset.navMove}"][data-step="${b.dataset.step}"]:not([disabled])`)?.focus();
      }),
  );
  if ($("#restore-nav-order"))
    $("#restore-nav-order").onclick = () => {
      localStorage.removeItem("tabOrder");
      applyNavOrder();
      render();
    };
  if ($("#compact-rows")) $("#compact-rows").onchange = (event) => applyCompact(event.target.checked);
  document.querySelectorAll("button[data-accent]").forEach(
    (b) =>
      (b.onclick = () => {
        applyAccent(b.dataset.accent);
        render();
      }),
  );
  document.querySelectorAll("button[data-appearance]").forEach(
    (b) =>
      (b.onclick = () => {
        applyAppearance(b.dataset.appearance);
        render();
      }),
  );
  document.querySelectorAll("[data-open-page]").forEach(
    (b) =>
      (b.onclick = () => {
        page = b.dataset.openPage;
        render();
      }),
  );
  if ($("#desktop-settings")) void loadDesktopSettings();
  if ($("#show-shortcuts")) $("#show-shortcuts").onclick = openShortcuts;
  if ($("#writing-settings")) {
    for (const [id, key] of [
      ["#autocorrect-toggle", "enabled"],
      ["#autocorrect-apostrophes", "apostrophes"],
      ["#autocorrect-spelling", "spelling"],
    ])
      $(id).onchange = (event) => OrbitAutocorrect.saveSettings({ [key]: event.target.checked });
    $("#autocorrect-rules").oninput = (event) => localStorage.setItem("autocorrectRules", event.target.value);
    $("#notes-password").onclick = async () => {
      if (await OrbitLocks.changePassword()) render();
    };
  }
  const exportAs = (mode) =>
    action(async () => {
      const message = await api.backup(mode);
      if (message) showNotice(message);
    });
  if ($("#export-backup")) $("#export-backup").onclick = () => exportAs("export");
  if ($("#export-csv")) $("#export-csv").onclick = () => exportAs("export-csv");
  if ($("#remove-examples")) $("#remove-examples").onclick = () => action(removeExamples);
  if ($("#import-backup")) $("#import-backup").onclick = () => void previewImport().catch((e) => showNotice(e.message));
}

const shortcutLabel = (accelerator) =>
  accelerator ? accelerator.replace("CommandOrControl", "Ctrl").replaceAll("+", " + ") : "Off";

async function loadDesktopSettings() {
  const show = (settings) => {
    const toggle = $("#notifications-toggle"),
      wrap = $("#global-shortcut-wrap");
    if (!toggle || !wrap) return;
    toggle.checked = settings.notifications;
    wrap.innerHTML = macPicker(
      "global-shortcut",
      "Quick add shortcut",
      settings.shortcuts.map((shortcut) => [shortcut, shortcutLabel(shortcut)]),
      settings.shortcut,
    );
    const change = async (values) => {
      try {
        show(await api.desktopSettings(values));
      } catch (error) {
        showNotice(error.message);
      }
    };
    toggle.onchange = (event) => void change({ notifications: event.target.checked });
    bindPickers({ "global-shortcut": (value) => void change({ shortcut: value }) }, wrap);
    if (settings.message) showNotice(settings.message);
  };
  try {
    show(await api.desktopSettings());
  } catch (error) {
    showNotice(error.message);
  }
}

/** Shows what an import would do before anything changes; differing items need an explicit choice. */
async function previewImport() {
  const plan = await api.backup("choose");
  if (!plan) return;
  const panel = $("#import-confirm");
  const changed = plan.changed.length
    ? `<p>${plan.changed.length} ${plan.changed.length === 1 ? "item differs" : "items differ"} from yours:</p>
       <ul class="import-list">${plan.changed.map((c) => `<li>${esc(c.title)}</li>`).join("")}</ul>
       <label class="toggle"><input type="checkbox" id="replace-changed" /> Replace ${plan.changed.length === 1 ? "it" : "them"} with the imported ${plan.changed.length === 1 ? "version" : "versions"}</label>`
    : "";
  panel.innerHTML = `<div class="import-preview">
      <p><strong>${plan.added}</strong> new ${plan.added === 1 ? "item" : "items"} will be added. ${plan.same} already here.</p>
      ${changed}
      <button class="primary" id="confirm-import">Import</button><button id="cancel-import">Cancel</button>
    </div>`;
  $("#cancel-import").onclick = () => panel.replaceChildren();
  $("#confirm-import").onclick = () =>
    action(async () => showNotice(await api.backup("restore", { replaceChanged: !!$("#replace-changed")?.checked })));
}
