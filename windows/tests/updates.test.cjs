const { test } = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const { UpdateManager, supportsUpdates } = require("../updates.cjs");

function fixture(enabled = true) {
  const updater = new EventEmitter();
  let checks = 0;
  let installs = [];
  updater.checkForUpdates = async () => {
    checks++;
    updater.emit("update-not-available");
  };
  updater.quitAndInstall = (...args) => installs.push(args);
  const manager = new UpdateManager({ updater, enabled, version: "0.3.4" });
  return { updater, manager, checks: () => checks, installs: () => installs };
}

test("only installed Windows copies update; portable, development and test copies stay offline", async () => {
  const config = { packaged: true, platform: "win32", portable: false, testData: false };
  assert.equal(supportsUpdates(config), true);
  for (const changes of [{ packaged: false }, { platform: "darwin" }, { portable: "Orbit.exe" }, { testData: "data" }])
    assert.equal(supportsUpdates({ ...config, ...changes }), false);
  const f = fixture(false);
  f.manager.start();
  await f.manager.check();
  assert.equal(f.checks(), 0);
  assert.equal(f.manager.snapshot().status, "unsupported");
  assert.throws(() => f.manager.install(), /not ready/);
});

test("checking is deduplicated and a failed check can be retried without quitting", async () => {
  const f = fixture();
  let finish;
  f.updater.checkForUpdates = () => new Promise((resolve) => (finish = resolve));
  const check = f.manager.check();
  assert.equal((await f.manager.check()).status, "checking");
  f.updater.emit("update-not-available");
  finish();
  await check;
  assert.equal(f.manager.snapshot().status, "current");
  f.updater.checkForUpdates = async () => {
    throw Error("Offline: private URL that should never reach the UI");
  };
  assert.equal((await f.manager.check()).status, "error");
  assert.equal(JSON.stringify(f.manager.snapshot()).includes("private URL"), false);
  f.updater.checkForUpdates = async () => f.updater.emit("update-not-available");
  assert.equal((await f.manager.check()).status, "current");
  assert.deepEqual(f.installs(), []);
});

test("downloads finish in the background and only an explicit restart installs", async () => {
  const f = fixture();
  assert.equal(f.updater.autoDownload, true);
  assert.equal(f.updater.autoInstallOnAppQuit, false);
  assert.equal(f.updater.allowPrerelease, false);
  assert.equal(f.updater.allowDowngrade, false);
  f.updater.emit("update-available", { version: "0.3.5" });
  f.updater.emit("download-progress", { percent: 42.9 });
  assert.equal(f.manager.snapshot().percent, 42);
  await f.manager.check();
  assert.equal(f.checks(), 0);
  assert.throws(() => f.manager.install(), /not ready/);
  f.updater.emit("update-downloaded", { version: "0.3.5" });
  assert.deepEqual(f.installs(), []);
  assert.equal(f.manager.snapshot().status, "downloaded");
  f.manager.install();
  assert.deepEqual(f.installs(), [[true, true]]);
  assert.throws(() => f.manager.install(), /not ready/);
});

test("download rejections are handled and a failed download cannot be installed", async () => {
  const f = fixture();
  f.updater.checkForUpdates = async () => {
    f.updater.emit("update-available", { version: "0.3.5" });
    return { downloadPromise: Promise.reject(Error("checksum mismatch")) };
  };
  assert.equal((await f.manager.check()).status, "error");
  assert.throws(() => f.manager.install(), /not ready/);
  f.updater.emit("error", Error("network error"));
  assert.equal(f.manager.snapshot().status, "error");
});

test("update events emit independent snapshots and installation failures remain recoverable", () => {
  const f = fixture();
  const snapshots = [];
  f.manager.onChange = (value) => snapshots.push(value);
  f.updater.emit("update-available", { version: "0.3.5" });
  f.updater.emit("download-progress", { percent: 200 });
  assert.equal(snapshots[0].percent, 0);
  assert.equal(snapshots[1].percent, 100);
  f.updater.emit("update-downloaded", { version: "0.3.5" });
  f.updater.quitAndInstall = () => {
    throw Error("missing installer");
  };
  assert.throws(() => f.manager.install(), /could not restart/);
  assert.equal(f.manager.snapshot().status, "error");
  f.manager.start();
  assert.equal(f.manager.timers.length, 2);
  f.manager.stop();
  assert.equal(f.manager.timers.length, 0);
});
