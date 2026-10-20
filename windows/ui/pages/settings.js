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
}
applyAppearance(localStorage.getItem("appearance") || "system");

function choiceButtons(attribute, values, current) {
  return values
    .map(
      (name) =>
        `<button data-${attribute}="${name}" aria-pressed="${current === name}">${name[0].toUpperCase() + name.slice(1)}</button>`,
    )
    .join("");
}

function renderSettings() {
  const root = document.documentElement.dataset;
  return `<h1>Settings</h1>
    <section class="settings-block">
      <h2>Appearance</h2>
      <div class="accent-options">${choiceButtons("appearance", appearances, root.appearance)}</div>
    </section>
    <section class="settings-block">
      <h2>Accent</h2>
      <div class="accent-options">${choiceButtons("accent", accents, root.accent)}</div>
    </section>
    <section class="settings-block" id="desktop-settings">
      <h2>Reminders & Shortcuts</h2>
      <label class="toggle"><input type="checkbox" id="notifications-toggle" /> Show reminders for tasks and habits</label>
      <label>Quick add from anywhere
        <select id="global-shortcut" aria-label="Quick add shortcut"></select>
      </label>
      <button id="show-shortcuts">Keyboard Shortcuts</button>
    </section>
    <section class="settings-block">
      <h2>Data</h2>
      <button id="export-backup">Export</button><button id="import-backup">Import</button>
      <p class="secondary">Exports contain your tasks, lists and habit history. No account details are included.</p>
      <div id="import-confirm"></div>
    </section>
    <button class="history-link" data-open-page="account">Account <span>${esc(state.email || "Not signed in")} →</span></button>`;
}

function bindSettings() {
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
  if ($("#export-backup"))
    $("#export-backup").onclick = () =>
      action(async () => {
        const message = await api.backup("export");
        if (message) showNotice(message);
      });
  if ($("#import-backup"))
    $("#import-backup").onclick = async () => {
      try {
        const count = await api.backup("choose");
        if (count === null) return;
        const panel = $("#import-confirm");
        panel.innerHTML = `<p>Import ${count} items? Matching items will be replaced; other items stay.</p><button id="confirm-import">Import and merge</button><button id="cancel-import">Cancel</button>`;
        $("#cancel-import").onclick = () => panel.replaceChildren();
        $("#confirm-import").onclick = () => action(async () => showNotice(await api.backup("restore")));
      } catch (e) {
        showNotice(e.message);
      }
    };
}

const shortcutLabel = (accelerator) =>
  accelerator ? accelerator.replace("CommandOrControl", "Ctrl").replaceAll("+", " + ") : "Off";

async function loadDesktopSettings() {
  const show = (settings) => {
    const toggle = $("#notifications-toggle"),
      select = $("#global-shortcut");
    if (!toggle || !select) return;
    toggle.checked = settings.notifications;
    select.innerHTML = settings.shortcuts
      .map((s) => `<option value="${esc(s)}" ${s === settings.shortcut ? "selected" : ""}>${shortcutLabel(s)}</option>`)
      .join("");
    if (settings.message) showNotice(settings.message);
  };
  show(await api.desktopSettings());
  $("#notifications-toggle").onchange = async (e) =>
    show(await api.desktopSettings({ notifications: e.target.checked }));
  $("#global-shortcut").onchange = async (e) => show(await api.desktopSettings({ shortcut: e.target.value }));
}
