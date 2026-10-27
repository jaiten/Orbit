// Update events touch only these controls, never re-render an editor while someone is typing.
let updateStatus = { status: "unsupported", currentVersion: "", version: null, percent: 0 };

function updateControls(value = updateStatus) {
  updateStatus = value;
  const ready = value.status === "downloaded";
  const restart = $("#restart-update");
  restart.hidden = !ready;
  restart.title = ready ? `Install Orbit ${value.version} and reopen` : "";
  const status = $("#update-status");
  const check = $("#check-updates");
  const install = $("#install-update");
  const messages = {
    unsupported: "Automatic updates are available in the installed Windows app.",
    idle: "Updates download automatically. You choose when to restart.",
    checking: "Checking for updates…",
    current: "You’re up to date.",
    downloading: `Downloading Orbit ${value.version}… ${value.percent}%`,
    downloaded: `Orbit ${value.version} is ready to install.`,
    installing: "Restarting to update…",
    error: "Couldn’t finish updating. Check your connection and try again.",
  };
  if (status) status.textContent = messages[value.status] || messages.idle;
  if (check) {
    check.hidden = value.status === "unsupported" || ready || value.status === "installing";
    check.disabled = ["checking", "downloading"].includes(value.status);
    check.textContent = value.status === "error" ? "Try again" : "Check for updates";
  }
  if (install) install.hidden = !ready;
}

async function restartToUpdate() {
  try {
    if (document.querySelector("dialog[open]") || inlineDraft.trim() || $("#inline-task-input")?.value.trim()) {
      showNotice("Finish or clear your draft before restarting to update.");
      return;
    }
    if (page === "note") await saveNote(true);
    updateControls(await api.updates("install"));
  } catch (error) {
    showNotice(error.message);
  }
}

function bindUpdates() {
  updateControls();
  if ($("#check-updates"))
    $("#check-updates").onclick = async () => {
      try {
        updateControls(await api.updates("check"));
      } catch (error) {
        showNotice(error.message);
      }
    };
  if ($("#install-update")) $("#install-update").onclick = () => void restartToUpdate();
}

$("#restart-update").onclick = () => void restartToUpdate();
if (api.onUpdateStatus) api.onUpdateStatus(updateControls);
if (api.updates)
  void api
    .updates("status")
    .then(updateControls)
    .catch(() => {});
