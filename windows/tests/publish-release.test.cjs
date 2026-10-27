const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { publishRelease } = require("../scripts/publish-release.cjs");

test("a release stays in draft until every asset is present, then repeated runs leave it untouched", () => {
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-release-"));
  const commit = "a".repeat(40);
  const files = ["latest.yml", "Orbit-Setup-0.3.4.exe", "Orbit-Setup-0.3.4.exe.blockmap", "Orbit-0.3.4.exe"];
  let release = null;
  let omitAsset = true;
  let uploads = 0;
  const gh = (...args) => {
    assert.equal(args[0], "release", "Drafts must be looked up through a draft-aware API");
    switch (args[1]) {
      case "view":
        if (release) return JSON.stringify(release);
        throw Object.assign(Error("missing release"), { stderr: "release not found" });
      case "create":
        release = { isDraft: true, targetCommitish: commit, assets: [] };
        return "";
      case "upload":
        uploads++;
        release.assets = files
          .slice(omitAsset ? 1 : 0)
          .map((name) => ({ name, size: fs.statSync(path.join(dist, name)).size }));
        return "";
      case "edit":
        assert.equal(release.assets.length, files.length);
        assert.ok(args.includes("--draft=false"));
        release.isDraft = false;
        return "";
      default:
        throw Error("Unexpected command");
    }
  };
  try {
    files.forEach((name) => fs.writeFileSync(path.join(dist, name), name));
    const options = { version: "0.3.4", repo: "jaiten/Orbit", commit, dist, gh };
    assert.throws(() => publishRelease(options), /upload incomplete/);
    assert.equal(release.isDraft, true);
    omitAsset = false;
    assert.match(publishRelease(options), /Published https/);
    assert.equal(release.isDraft, false);
    const count = uploads;
    assert.match(publishRelease(options), /already published/);
    assert.equal(uploads, count, "A public release must not be overwritten");
    release.isDraft = true;
    release.targetCommitish = "b".repeat(40);
    assert.throws(() => publishRelease(options), /another commit/);
  } finally {
    fs.rmSync(dist, { recursive: true, force: true });
  }
});
