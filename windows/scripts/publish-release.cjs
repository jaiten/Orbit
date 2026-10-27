// Publish only validated CI artifacts. An existing public release is never overwritten.
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

function publishRelease({ version, repo, commit, dist, gh }) {
  if (!/^\d+\.\d+\.\d+$/.test(version || "") || repo !== "jaiten/Orbit" || !/^[a-f0-9]{40}$/.test(commit || ""))
    throw Error("Invalid release coordinates");
  const tag = `v${version}`;
  const files = [
    "latest.yml",
    `Orbit-Setup-${version}.exe`,
    `Orbit-Setup-${version}.exe.blockmap`,
    `Orbit-${version}.exe`,
  ].map((file) => path.resolve(dist, file));
  files.forEach((file) => {
    if (!fs.statSync(file).size) throw Error(`Empty release asset: ${file}`);
  });
  // The REST /releases/tags endpoint cannot find an unpublished draft with no tag ref.
  const findRelease = () => {
    try {
      return JSON.parse(gh("release", "view", tag, "--repo", repo, "--json", "isDraft,targetCommitish,assets"));
    } catch (error) {
      if (!/HTTP 404|release not found/i.test(String(error.stderr))) throw error;
      return null;
    }
  };
  let release = findRelease();
  if (release && !release.isDraft)
    return `${tag} is already published; bump windows/package.json to ship another update.`;
  if (release && release.targetCommitish !== commit) throw Error("Existing draft belongs to another commit");
  if (!release) {
    const notes = path.join(os.tmpdir(), "orbit-windows-release-notes.txt");
    fs.writeFileSync(
      notes,
      `Orbit ${version} for Windows\n\nRun Orbit-Setup-${version}.exe to install or upgrade. Your tasks, notes, habits, preferences and sign-in stay on this PC.\n\nInstalled Orbit versions from 0.3.4 download future updates automatically and offer a restart when ready. You can also check in Settings → Updates. The portable executable requires manual updates.\n`,
    );
    gh(
      "release",
      "create",
      tag,
      "--repo",
      repo,
      "--target",
      commit,
      "--draft",
      "--title",
      `Orbit for Windows ${version}`,
      "--notes-file",
      notes,
    );
  }
  gh("release", "upload", tag, ...files, "--repo", repo, "--clobber");
  release = findRelease();
  for (const file of files) {
    const asset = release.assets.find((item) => item.name === path.basename(file));
    if (!asset || asset.size !== fs.statSync(file).size) throw Error(`Release upload incomplete: ${file}`);
  }
  // Make the feed discoverable only after the installer, checksum feed and blockmap are all present.
  gh("release", "edit", tag, "--repo", repo, "--draft=false", "--latest");
  return `Published https://github.com/${repo}/releases/tag/${tag}`;
}
if (require.main === module) {
  console.log(
    publishRelease({
      version: process.env.ORBIT_RELEASE_VERSION,
      repo: process.env.GITHUB_REPOSITORY,
      commit: process.env.GITHUB_SHA,
      dist: "dist",
      gh: (...args) => execFileSync("gh", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }),
    }),
  );
}
module.exports = { publishRelease };
