// Desktop integration: native reminders, the tray icon and the global quick-add shortcut.
const { app, Tray, Menu, Notification, globalShortcut, nativeImage } = require("electron");
const { ReminderScheduler } = require("./reminders.cjs");

/** Offered global shortcuts; "" turns it off. */
const SHORTCUTS = ["CommandOrControl+Shift+Space", "CommandOrControl+Alt+Space", "CommandOrControl+Shift+O", ""];
const DEFAULT_SHORTCUT = SHORTCUTS[0];

function setupDesktop({ window, store, iconPath }) {
  let tray = null;
  const icon = nativeImage.createFromPath(iconPath);
  const showWindow = () => {
    if (window.isMinimized()) window.restore();
    window.show();
    window.focus();
  };
  const quickAdd = () => {
    showWindow();
    window.webContents.send("quick-add");
  };

  const settings = () => ({
    notifications: store.setting("notifications") !== "off",
    shortcut: store.setting("globalShortcut") ?? DEFAULT_SHORTCUT,
    shortcuts: SHORTCUTS,
    // Minutes after midnight for the evening check-in, or null when it is off (the default).
    eveningCheckIn: /^\d+$/.test(store.setting("eveningCheckIn") || "")
      ? Number(store.setting("eveningCheckIn"))
      : null,
  });

  const scheduler = new ReminderScheduler({
    read: () => store.rows(),
    enabled: () => settings().notifications,
    options: () => ({ eveningMinutes: settings().eveningCheckIn }),
    show: (reminder) => {
      if (!Notification.isSupported()) return;
      const notification = new Notification({ title: reminder.title, body: reminder.body, icon, silent: false });
      notification.on("click", showWindow);
      notification.show();
    },
  });

  /** Registers the chosen shortcut; returns false when another app already uses it. */
  const applyShortcut = (accelerator) => {
    globalShortcut.unregisterAll();
    if (!accelerator) return true;
    try {
      return globalShortcut.register(accelerator, quickAdd);
    } catch {
      return false;
    }
  };

  const update = ({ notifications, shortcut, eveningCheckIn }) => {
    let message = null;
    if (eveningCheckIn === null) store.setting("eveningCheckIn", "off");
    else if (Number.isInteger(eveningCheckIn) && eveningCheckIn >= 0 && eveningCheckIn < 1440)
      store.setting("eveningCheckIn", String(eveningCheckIn));
    if (typeof notifications === "boolean") store.setting("notifications", notifications ? "on" : "off");
    if (typeof shortcut === "string") {
      if (!SHORTCUTS.includes(shortcut)) throw Error("Choose one of the offered shortcuts");
      if (!applyShortcut(shortcut)) {
        applyShortcut(settings().shortcut);
        message = "That shortcut is used by another app. Your previous shortcut is still active.";
      } else store.setting("globalShortcut", shortcut);
    }
    scheduler.reschedule();
    return { ...settings(), message };
  };

  try {
    tray = new Tray(icon.resize({ width: 16, height: 16 }));
    tray.setToolTip("Orbit");
    tray.setContextMenu(
      Menu.buildFromTemplate([
        { label: "Quick Add", click: quickAdd },
        { label: "Open Orbit", click: showWindow },
        { type: "separator" },
        { label: "Quit Orbit", click: () => app.quit() },
      ]),
    );
    tray.on("click", showWindow);
  } catch {
    tray = null; // Some desktops have no tray; closing the window then quits as before.
  }

  // With a tray, closing the window keeps Orbit running so reminders and the shortcut still work.
  let quitting = false;
  app.on("before-quit", () => {
    quitting = true;
  });
  window.on("close", (event) => {
    if (tray && !quitting) {
      event.preventDefault();
      window.hide();
    }
  });
  app.on("will-quit", () => globalShortcut.unregisterAll());

  applyShortcut(settings().shortcut);
  scheduler.reschedule();
  return { scheduler, settings, update, quickAdd };
}

module.exports = { setupDesktop, SHORTCUTS };
