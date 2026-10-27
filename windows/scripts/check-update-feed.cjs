const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const assert = require("node:assert/strict");
const yaml = require("js-yaml");

function checkUpdateFeed(dist, version) {
  const read = (file) => yaml.load(fs.readFileSync(path.join(dist, file), "utf8"));
  const feed = read("latest.yml");
  assert.equal(feed.version, version, "Update feed must match the installer version");
  const installer = `Orbit-Setup-${version}.exe`;
  assert.equal(feed.files.length, 1, "Only the installed app belongs in the update feed");
  assert.equal(feed.files[0].url, installer, "Updates must use the NSIS installer");
  assert.equal(feed.path, installer);
  const bytes = fs.readFileSync(path.join(dist, installer));
  const hash = createHash("sha512").update(bytes).digest("base64");
  assert.equal(feed.files[0].sha512, hash, "Installer must match the feed checksum");
  assert.equal(feed.sha512, hash);
  assert.equal(feed.files[0].size, bytes.length);
  assert.ok(fs.statSync(path.join(dist, installer + ".blockmap")).size > 0);
  const config = read("win-unpacked/resources/app-update.yml");
  assert.equal(config.provider, "github");
  assert.equal(config.owner, "jaiten");
  assert.equal(config.repo, "Orbit");
  assert.ok(!config.token && !config.private, "Update checks must not require bundled credentials");
}

if (require.main === module) {
  checkUpdateFeed(path.resolve(__dirname, "../dist"), require("../package.json").version);
  console.log("PASS: GitHub feed points to the versioned installer with a matching SHA-512 checksum");
}
module.exports = { checkUpdateFeed };
