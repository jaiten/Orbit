// Account: sign-in, email confirmation, devices and sign-out. Sync status lives here too.
function accountSection() {
  if (state.email)
    return `<p>${esc(state.email)}</p><button id="sync-now">Sync now</button><button id="show-devices">Devices & active sign-ins</button><button id="change-password">Change password</button><div id="devices-panel"></div><button id="signout">Sign out / Switch account</button><div class="delete-account"><p class="secondary">Permanently deletes your Orbit account and synced planner data, then clears this PC. Export a backup first if you want to keep a copy.</p><button id="delete-account" class="danger">Delete account</button></div>`;
  const disabled = !state.configured ? "disabled" : "";
  return `<form id="account"><label>Email<input name="email" type="email" autocomplete="email" value="${esc(accountEmail)}" required></label><label>Password<input name="password" type="password" autocomplete="current-password" minlength="8" required></label><div><button class="primary" type="submit" ${disabled}>Sign in</button><button type="button" id="forgot-password">Forgot password?</button><button type="button" id="signup" ${disabled}>Create account</button></div></form><details class="confirmation"><summary>Email confirmation</summary><form id="confirm-account"><label>Confirmation code (if provided)<input name="code" autocomplete="one-time-code" inputmode="numeric" required></label><button class="primary">Confirm account</button><button type="button" id="resend-code">Resend confirmation email</button></form><p class="secondary">Open the newest confirmation email and tap its link, then sign in above. If your email provides a code, enter it here.</p></details>${!state.configured ? '<p class="secondary">Backend setup is still in progress. Everything you add is saved locally.</p>' : ""}`;
}

function renderAccount() {
  return `<button id="account-back" class="account-back"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m14 6-6 6 6 6M8 12h13"/></svg>Back to settings</button><h1>Account</h1>
    <section class="settings-block">
      <h2>Sync</h2>
      <p id="sync-details">${esc(state.status)}</p>
      <p class="secondary">Sign in with the same account on your iPhone to sync. Everything is saved on this PC first.</p>
      ${accountSection()}
    </section>`;
}

function bindAccount() {
  if ($("#account-back")) $("#account-back").onclick = () => void goTo("settings");
  if ($("#change-password")) $("#change-password").onclick = () => openDialog($("#password-editor"));
  if ($("#forgot-password"))
    $("#forgot-password").onclick = () =>
      action(async () => {
        const email = $("#account").elements.email.value.trim();
        if (!email) throw Error("Enter your email first");
        showNotice(await api.auth("recover", email, ""));
      });
  if ($("#show-devices")) $("#show-devices").onclick = () => void showDevices().catch((e) => showNotice(e.message));
  if ($("#confirm-account")) {
    $("#confirm-account").onsubmit = (e) => {
      e.preventDefault();
      void action(() => confirmAccount("verify"));
    };
    $("#resend-code").onclick = () => action(() => confirmAccount("resend"));
  }
  if ($("#sync-now")) $("#sync-now").onclick = () => action(() => api.sync());
  if ($("#signout")) $("#signout").onclick = () => action(() => api.auth("out"));
  if ($("#delete-account"))
    $("#delete-account").onclick = (event) => {
      const button = event.currentTarget;
      if (button.dataset.confirm !== "yes") {
        button.dataset.confirm = "yes";
        button.textContent = "Confirm permanent deletion";
        return;
      }
      action(async () => showNotice(await api.auth("delete")));
    };
  if ($("#account")) {
    const auth = (mode) => {
      const f = $("#account");
      if (!f.reportValidity()) return;
      const email = f.elements.email.value.trim(),
        password = f.elements.password.value;
      accountEmail = email;
      action(async () => {
        const message = await api.auth(mode, email, password);
        if (message !== "Signed in") showNotice(message);
      });
    };
    $("#account").onsubmit = (e) => {
      e.preventDefault();
      auth("in");
    };
    $("#account").onkeydown = (e) => {
      if (e.key !== "Enter" || e.isComposing || e.target.tagName !== "INPUT") return;
      e.preventDefault();
      const submit = $("#account button[type=submit]");
      if (!submit.disabled) $("#account").requestSubmit(submit);
    };
    $("#signup").onclick = () => auth("up");
  }
}

async function confirmAccount(mode) {
  const email = $("#account").elements.email.value.trim();
  accountEmail = email;
  if (!email || !$("#account").elements.email.reportValidity()) return;
  if (mode === "resend" && Date.now() < resendAfter)
    throw Error("Please wait a minute before requesting another code.");
  const code = $("#confirm-account").elements.code.value;
  if (mode === "verify" && !code.trim()) throw Error("Enter the newest confirmation code from your email.");
  const message = await api.auth(mode, email, code);
  if (mode === "resend") resendAfter = Date.now() + 60000;
  if (message !== "Signed in") showNotice(message);
}

async function showDevices() {
  const devices = await api.devices();
  const panel = $("#devices-panel");
  if (!panel) return;
  panel.innerHTML =
    `<h3>${devices.length} active sign-ins</h3><p class="secondary">Removing access blocks Orbit sync. Downloaded data stays on the device. A device can have multiple sign-ins.</p>` +
    devices
      .map(
        (d) =>
          `<div class="device-row"><span>${esc(d.name)}${d.current ? " · This device" : ""}<small class="secondary">Last active ${esc(new Date(d.last_seen).toLocaleString())}</small></span>${d.current ? "" : `<button data-remove-device="${esc(d.id)}">Remove access</button>`}</div>`,
      )
      .join("");
  panel.querySelectorAll("[data-remove-device]").forEach(
    (b) =>
      (b.onclick = async () => {
        if (b.dataset.confirm !== "yes") {
          b.dataset.confirm = "yes";
          b.textContent = "Confirm removal";
          return;
        }
        try {
          b.disabled = true;
          await api.removeDevice(b.dataset.removeDevice);
          await showDevices();
        } catch (e) {
          showNotice(e.message);
          b.disabled = false;
        }
      }),
  );
}
