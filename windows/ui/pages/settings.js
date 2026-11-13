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

const calendarToggle = (calendar, attribute, subtitle) =>
  `<label class="toggle calendar-toggle" data-event-color="${/^#[0-9a-f]{6}$/i.test(calendar.color || "") ? calendar.color : "var(--muted)"}"><input type="checkbox" ${attribute}="${esc(calendar.id)}" ${calendar.shown === false ? "" : "checked"} /><span class="calendar-name"><i></i><span>${esc(calendar.title)}${subtitle ? `<small>${esc(subtitle)}</small>` : ""}</span></span></label>`;

/** Settings → Calendar: Google and Microsoft accounts linked on this PC, then Apple calendars from the iPhone. */
function calendarList() {
  const { accounts = [], calendars = [], available = {} } = state.linkedCalendars || {};
  const service = { google: "Google", microsoft: "Outlook" };
  const linkedAccounts = accounts
    .map(
      (account) => `<div class="linked-account">
        <div class="linked-account-head"><span><strong>${esc(service[account.provider])}</strong><small>${esc(account.email)}</small></span><button data-disconnect-account="${esc(account.id)}">Disconnect</button></div>
        ${account.error ? `<p class="secondary linked-account-error">${esc(account.error)}</p>` : ""}
        <div class="calendar-toggles">${calendars
          .filter((calendar) => calendar.account === account.id)
          .sort((a, b) => !!b.primary - !!a.primary || String(a.title).localeCompare(String(b.title)))
          .map((calendar) => calendarToggle(calendar, "data-linked-calendar", calendar.writable ? "" : "Read-only"))
          .join("")}</div>
      </div>`,
    )
    .join("");
  const connect = ["google", "microsoft"]
    .map(
      (provider) =>
        `<button data-connect-calendar="${provider}" ${available[provider] ? "" : "disabled"}>Connect ${provider === "google" ? "Google Calendar" : "Outlook / Microsoft 365"}</button>`,
    )
    .join("");
  const apple = rows("calendars").sort(
    (a, b) =>
      String(a.account || "").localeCompare(String(b.account || "")) || String(a.title).localeCompare(String(b.title)),
  );
  return `<h3>Google & Outlook</h3>
    <p class="secondary">Connect an account to see and edit its calendars here. Changes are saved straight to the calendar.</p>
    ${linkedAccounts}
    <div class="fields calendar-connect">${connect}</div>
    ${available.google || available.microsoft ? "" : '<p class="secondary">Calendar sign-in isn\'t set up in this build of Orbit.</p>'}
    <h3>Apple calendars</h3>
    ${
      apple.length
        ? `<p class="secondary">Your iCloud calendars, shared by Orbit on iPhone. Turning one off hides it on both devices. Edits made here are saved to the calendar the next time Orbit syncs on your iPhone.</p><div class="calendar-toggles">${apple.map((calendar) => calendarToggle(calendar, "data-calendar-shown", calendar.account)).join("")}</div>`
        : '<p class="secondary">To see iCloud calendars here, connect calendars in Orbit on iPhone (Settings → Calendars) and sign in to the same Orbit account.</p>'
    }`;
}

/** Settings → Sidebar order: drag a row (anywhere but its buttons); the others slide out of the way. */
function bindNavOrderDrag() {
  const list = $(".nav-order-list");
  if (!list) return;
  list.querySelectorAll("li[data-nav-item]").forEach((item) => {
    item.onpointerdown = (down) => {
      if (down.button !== 0 || down.target.closest("button")) return;
      down.preventDefault();
      item.setPointerCapture(down.pointerId);
      item.classList.add("dragging");
      const offset = down.clientY - item.getBoundingClientRect().top;
      let shift = 0;
      item.onpointermove = (move) => {
        // The row follows the pointer and trades places with a neighbour once it passes that neighbour's middle.
        const top = move.clientY - offset;
        const rows = [...list.querySelectorAll("li[data-nav-item]")];
        const previous = rows[rows.indexOf(item) - 1],
          next = rows[rows.indexOf(item) + 1];
        if (previous && top < previous.getBoundingClientRect().top + previous.offsetHeight / 2) previous.before(item);
        else if (next && top + item.offsetHeight > next.getBoundingClientRect().top + next.offsetHeight / 2)
          next.after(item);
        shift = top - (item.getBoundingClientRect().top - shift);
        item.style.transform = `translateY(${shift}px)`;
      };
      const finish = () => {
        item.onpointermove = item.onpointerup = item.onpointercancel = null;
        item.classList.remove("dragging");
        item.style.transform = "";
        const order = [...list.querySelectorAll("li[data-nav-item]")].map((row) => row.dataset.navItem);
        if (order.join(",") !== navOrder().join(",")) saveNavOrder(order);
        render();
      };
      item.onpointerup = finish;
      item.onpointercancel = finish;
    };
  });
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
            `<li data-nav-item="${name}"><span class="nav-order-grip" aria-hidden="true">⠿</span><span>${NAV_NAMES[name]}</span><kbd>Ctrl+${index + 1}</kbd><button class="icon-button small" data-nav-move="${name}" data-step="-1" aria-label="Move ${NAV_NAMES[name]} up" ${index === 0 ? "disabled" : ""}>↑</button><button class="icon-button small" data-nav-move="${name}" data-step="1" aria-label="Move ${NAV_NAMES[name]} down" ${index === all.length - 1 ? "disabled" : ""}>↓</button></li>`,
        )
        .join("")}</ol>
      <button id="restore-nav-order" ${localStorage.getItem("tabOrder") ? "" : "disabled"}>Restore default order</button>
    </section>
    <section class="settings-block" id="today-preferences"><h2>Today & Progress</h2>
      <div class="settings-field"><span>Day starts at</span>${macPicker(
        "day-start",
        "Day starts at",
        OrbitPlanner.DAY_START_CHOICES.map((minutes) => [String(minutes), OrbitPlanner.dayStartLabel(minutes)]),
        String(dayStart()),
      )}</div>
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
  document.querySelectorAll("[data-linked-calendar]").forEach((box) => {
    box.onchange = () =>
      void action(() =>
        api.linkedCalendars({ command: "show", calendar: box.dataset.linkedCalendar, shown: box.checked }),
      );
  });
  document.querySelectorAll("[data-disconnect-account]").forEach((button) => {
    button.onclick = () =>
      void action(() => api.linkedCalendars({ command: "disconnect", account: button.dataset.disconnectAccount }));
  });
  // Sign-in finishes in the browser, which can take a while, so it doesn't hold up other actions.
  document.querySelectorAll("[data-connect-calendar]").forEach((button) => {
    button.onclick = async () => {
      button.disabled = true;
      showNotice("Finish signing in in your browser, then come back to Orbit.");
      try {
        const account = await api.linkedCalendars({ command: "connect", provider: button.dataset.connectCalendar });
        showNotice(`Connected ${account.email}.`);
      } catch (error) {
        showNotice(error.message);
      } finally {
        button.disabled = false;
        await load(true);
      }
    };
  });
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
  bindNavOrderDrag();
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
