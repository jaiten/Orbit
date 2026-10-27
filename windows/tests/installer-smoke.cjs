// Exercise the packaged installer and an in-place reinstall with real planner data.
const { _electron: electron } = require("playwright");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const assert = require("node:assert/strict");
const http = require("node:http");
const yaml = require("js-yaml");
const run = promisify(execFile);
(async () => {
  assert.equal(process.platform, "win32", "The installer smoke test runs on Windows");
  const dist = path.resolve(__dirname, "../dist");
  const installer = path.join(
    dist,
    fs.readdirSync(dist).find((file) => /^Orbit-Setup-.*\.exe$/.test(file)),
  );
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-install-"));
  const destination = path.join(root, "app");
  const userData = path.join(root, "data");
  const executablePath = path.join(destination, "Orbit.exe");
  const install = () => run(installer, ["/S", `/D=${destination}`], { timeout: 180000 });
  const launch = () =>
    electron.launch({ executablePath, args: [], env: { ...process.env, ORBIT_TEST_DATA: userData } });
  let app;
  let corruptFeed = true;
  let downloads = 0;
  const feed = yaml.load(fs.readFileSync(path.join(dist, "latest.yml"), "utf8"));
  const server = http.createServer((request, response) => {
    if (request.url.split("?")[0] === "/latest.yml") {
      const info = structuredClone(feed);
      if (corruptFeed) info.sha512 = info.files[0].sha512 = Buffer.alloc(64).toString("base64");
      response.writeHead(200, { "Content-Type": "text/yaml" });
      response.end(yaml.dump(info));
    } else if (request.url.split("?")[0] === "/" + path.basename(installer)) {
      downloads++;
      response.writeHead(200, { "Content-Length": fs.statSync(installer).size });
      fs.createReadStream(installer).pipe(response);
    } else {
      response.writeHead(404);
      response.end();
    }
  });
  try {
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    await install();
    assert.ok(fs.existsSync(executablePath), "Installer did not install Orbit.exe");
    app = await launch();
    let page = await app.firstWindow();
    const input = page.getByRole("textbox", { name: "New task", exact: true });
    await input.fill("Keep this through an upgrade");
    await input.press("Enter");
    await page.getByRole("checkbox", { name: "Complete Keep this through an upgrade", exact: true }).waitFor();
    await page.keyboard.press("Control+6");
    await page.getByRole("button", { name: "Dark", exact: true }).click();
    // Run the real NSIS updater against a loopback feed, never the public release feed.
    await app.evaluate((_, url) => global.orbitTestEnableUpdates(url), `http://127.0.0.1:${server.address().port}`);
    await page.getByRole("button", { name: "Check for updates", exact: true }).click();
    await page.getByRole("button", { name: "Try again", exact: true }).waitFor({ timeout: 120000 });
    assert.equal(await page.locator("#restart-update").isVisible(), false, "Bad checksum offered an install");
    corruptFeed = false;
    await page.getByRole("button", { name: "Try again", exact: true }).click();
    await page.locator("#restart-update").waitFor({ state: "visible", timeout: 120000 });
    assert.ok(downloads >= 2, "The updater did not fetch and verify the actual installer");
    assert.equal((await page.evaluate(() => window.orbit.updates())).status, "downloaded");
    // Downloading must never quit the app or install just because it closes below.
    await page.keyboard.press("Control+1");
    await page.getByRole("checkbox", { name: "Complete Keep this through an upgrade", exact: true }).waitFor();
    await app.close();
    app = null;
    // Reinstall exercises the same NSIS replacement path used by a newer version.
    await install();
    app = await launch();
    page = await app.firstWindow();
    await page.getByRole("checkbox", { name: "Complete Keep this through an upgrade", exact: true }).waitFor();
    assert.equal(await page.locator("html").getAttribute("data-appearance"), "dark", "Upgrade lost preferences");
    await app.close();
    app = null;
    const uninstaller = fs.readdirSync(destination).find((file) => /^Uninstall.*\.exe$/.test(file));
    assert.ok(uninstaller, "Installer did not provide an uninstaller");
    await run(path.join(destination, uninstaller), ["/S"], { timeout: 180000 });
    assert.ok(fs.existsSync(path.join(userData, "orbit.sqlite")), "Uninstall removed planner data");
    console.log("PASS: installed updater rejects a bad checksum, downloads a valid installer, and waits for restart");
    console.log("PASS: install, launch, reinstall preserves tasks/preferences, uninstall preserves planner data");
  } finally {
    if (app) await app.close();
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(root, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 });
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
