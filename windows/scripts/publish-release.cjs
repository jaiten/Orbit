// Publish only validated CI artifacts. An existing public release is never overwritten.
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

const version = process.env.ORBIT_RELEASE_VERSION;
const repo = process.env.GITHUB_REPOSITORY;
const commit = process.env.GITHUB_SHA;
if (!/^\d+\.\d+\.\d+$/.test(version || "") || repo !== "jaiten/Orbit" || !/^[a-f0-9]{40}$/.test(commit || ""))
  throw Error("Invalid release coordinates");
const tag = `v${version}`;
const gh = (...args) => execFileSync("gh", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
const files = [
  "latest.yml",
  `Orbit-Setup-${version}.exe`,
  `Orbit-Setup-${version}.exe.blockmap`,
  `Orbit-${version}.exe`,
].map((file) => path.resolve("dist", file));
files.forEach((file) => {
  if (!fs.statSync(file).size) throw Error(`Empty release asset: ${file}`);
});
let release;
try {
  release = JSON.parse(gh("api", `repos/${repo}/releases/tags/${tag}`));
} catch (error) {
  if (!String(error.stderr).includes("HTTP 404")) throw error;
}
if (release && !release.draft) {
  console.log(`${tag} is already published; bump windows/package.json to ship another update.`);
  process.exit(0);
}
if (release && release.target_commitish !== commit) throw Error("Existing draft belongs to another commit");
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
release = JSON.parse(gh("api", `repos/${repo}/releases/tags/${tag}`));
for (const file of files) {
  const asset = release.assets.find((item) => item.name === path.basename(file));
  if (!asset || asset.size !== fs.statSync(file).size) throw Error(`Release upload incomplete: ${file}`);
}
// Make the feed discoverable only after the installer, checksum feed and blockmap are all present.
gh("release", "edit", tag, "--repo", repo, "--draft=false", "--latest");
console.log(`Published https://github.com/${repo}/releases/tag/${tag}`);
