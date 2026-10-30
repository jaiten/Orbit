// Own the update lifecycle in the main process. The renderer never chooses a feed or installer path.
class UpdateManager {
  constructor({ updater, version, enabled, onChange = () => {} }) {
    this.updater = updater;
    this.onChange = onChange;
    this.state = { status: enabled ? "idle" : "unsupported", currentVersion: version, version: null, percent: 0 };
    this.timers = [];
    if (!enabled) return;
    updater.autoDownload = true;
    updater.autoInstallOnAppQuit = false;
    updater.autoRunAppAfterInstall = true;
    updater.allowPrerelease = false;
    updater.allowDowngrade = false;
    updater.on("checking-for-update", () => this.set({ status: "checking" }));
    updater.on("update-not-available", () => this.set({ status: "current", version: null, percent: 0 }));
    updater.on("update-available", (info) => this.set({ status: "downloading", version: info.version, percent: 0 }));
    updater.on("download-progress", ({ percent }) => {
      if (this.state.status !== "downloading") return;
      this.set({ percent: Math.floor(Math.max(0, Math.min(100, Number(percent) || 0))) });
    });
    updater.on("update-downloaded", (info) => this.set({ status: "downloaded", version: info.version, percent: 100 }));
    // Keep network errors in Settings, without disrupting planning or exposing download URLs.
    updater.on("error", () => this.set({ status: "error", percent: 0 }));
  }

  snapshot() {
    return { ...this.state };
  }

  set(change) {
    this.state = { ...this.state, ...change };
    this.onChange(this.snapshot());
  }

  async check() {
    if (["unsupported", "checking", "downloading", "downloaded", "installing"].includes(this.state.status))
      return this.snapshot();
    this.set({ status: "checking", version: null, percent: 0 });
    try {
      const result = await this.updater.checkForUpdates();
      // Automatic downloads can reject after the check succeeds (offline, disk full,
      // checksum failure). Consume that promise as well as the updater's error event.
      if (result?.downloadPromise) await result.downloadPromise;
    } catch {
      this.set({ status: "error" });
    }
    return this.snapshot();
  }

  install() {
    if (this.state.status !== "downloaded") throw Error("The update is not ready yet.");
    this.set({ status: "installing" });
    try {
      this.updater.quitAndInstall(true, true);
    } catch {
      this.set({ status: "error" });
      throw Error("Orbit could not restart to update. Please try again from Settings.");
    }
    return this.snapshot();
  }

  start() {
    if (this.state.status === "unsupported" || this.timers.length) return;
    const repeat = setInterval(() => void this.check(), 4 * 60 * 60 * 1000);
    this.timers = [repeat];
    this.timers.forEach((timer) => timer.unref());
    void this.check();
  }

  stop() {
    this.timers.forEach((timer) => clearTimeout(timer));
    this.timers = [];
  }
}

function supportsUpdates({ packaged, platform, portable, testData }) {
  return packaged && platform === "win32" && !portable && !testData;
}

module.exports = { UpdateManager, supportsUpdates };
