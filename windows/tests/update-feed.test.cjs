const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { createHash } = require("node:crypto");
const yaml = require("js-yaml");
const { checkUpdateFeed } = require("../scripts/check-update-feed.cjs");

test("publishing refuses a damaged installer or a portable executable as the update target", () => {
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-feed-"));
  const installer = "Orbit-Setup-0.3.4.exe";
  const bytes = Buffer.from("fixture installer bytes");
  const hash = createHash("sha512").update(bytes).digest("base64");
  const feed = {
    version: "0.3.4",
    path: installer,
    sha512: hash,
    files: [{ url: installer, sha512: hash, size: bytes.length }],
  };
  const writeFeed = () => fs.writeFileSync(path.join(dist, "latest.yml"), yaml.dump(feed));
  try {
    fs.mkdirSync(path.join(dist, "win-unpacked/resources"), { recursive: true });
    fs.writeFileSync(
      path.join(dist, "win-unpacked/resources/app-update.yml"),
      yaml.dump({ provider: "github", owner: "jaiten", repo: "Orbit" }),
    );
    fs.writeFileSync(path.join(dist, installer), bytes);
    fs.writeFileSync(path.join(dist, installer + ".blockmap"), "fixture blockmap");
    writeFeed();
    checkUpdateFeed(dist, "0.3.4");
    assert.throws(() => checkUpdateFeed(dist, "0.3.5"), /must match the installer version/);
    fs.appendFileSync(path.join(dist, installer), "corruption");
    assert.throws(() => checkUpdateFeed(dist, "0.3.4"), /checksum/);
    fs.writeFileSync(path.join(dist, installer), bytes);
    feed.files[0].url = "Orbit-0.3.4.exe";
    writeFeed();
    assert.throws(() => checkUpdateFeed(dist, "0.3.4"), /NSIS installer/);
  } finally {
    fs.rmSync(dist, { recursive: true, force: true });
  }
});
