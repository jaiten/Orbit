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

function applyCompact(value) {
  document.documentElement.dataset.compact = String(value);
  localStorage.setItem("compactRows", String(value));
}
applyCompact(localStorage.getItem("compactRows") === "true");

function renderSettings() {
  const root = document.documentElement.dataset;
  return `<header class="page-head"><div><div class="eyebrow">Preferences</div><h1>Settings</h1></div></header>
    <button class="card account-row" data-open-page="account"><span>Account</span><span class="${state.email ? "secondary" : "account-sign-in"}">${esc(state.email || "Sign in")}</span></button>
    <section class="settings-block">
      <h2>Appearance</h2>
      <label class="toggle"><input type="checkbox" id="compact-rows" ${root.compact === "true" ? "checked" : ""} /> Compact habits and tasks</label>
      <div class="accent-options segmented" role="group" aria-label="Appearance">${choiceButtons("appearance", appearances, root.appearance)}</div>
    </section>
    <section class="settings-block">
      <h2>Accent</h2>
      <div class="accent-options segmented" role="group" aria-label="Accent">${choiceButtons("accent", accents, root.accent)}</div>
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
      <h2>Import & Export</h2>
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
