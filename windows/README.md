# Orbit for Windows

A dedicated Electron planner with a two-column Today view, lists, a calendar,
task and habit editing, habit history, and sync. Quick add understands phrases
such as `gym tomorrow 6am`. SQLite lives in Electron's userData directory.
The packaged executable does not need Node or a browser installation.

## Run and package

With Node 24:

```powershell
cd windows
npm ci
npm start
npm test
npm run test:desktop
npm run pack
```

If npm disables install scripts, first run `node node_modules/electron/install.js`.
Packaging creates `dist/Orbit-Setup-<version>.exe` (the installer) and
`dist/Orbit-<version>.exe` (portable). Windows CI uploads both in `Orbit-Windows`.
The installer installs for the current Windows user, adds Start menu and desktop
shortcuts, and provides an uninstaller. Install 0.3.4 or later once to enable
automatic updates from [GitHub Releases](https://github.com/jaiten/Orbit/releases/latest).
The app ID and user-data location are shared with the portable build, so upgrades
keep the local planner, preferences and sign-in data. Uninstalling keeps app data.
Installed Windows copies check after opening (15 seconds) and every four hours
while running, including in the tray. Updates download in the background. Choose
**Update ready — restart** in the sidebar or **Settings → Updates → Restart to
update** to install and reopen Orbit. Closing the app does not install an update
without that action. **Check for updates** also checks manually. Offline checks
stay in Settings and retry on the next check. Notes save before restart; unfinished
capture drafts block a restart until finished or cleared. Portable and development
copies do not auto-update.

## Publish an update

Bump `windows/package.json` and its lockfile (`npm version patch --no-git-tag-version`
inside `windows`), then push to `main`. After lint, unit, renderer, desktop,
feed-checksum and installer tests pass, Windows CI publishes `v<version>` as the
latest GitHub release. The release contains the NSIS installer, its blockmap,
`latest.yml` (version and SHA-512 checksum), and the optional portable executable.
The installer has the public GitHub feed bundled; no GitHub token is shipped.

Uploads finish in a draft before the release becomes discoverable. Existing public
versions are never overwritten; publishing another update requires another version
bump. PRs build artifacts but cannot publish. Manual Windows workflow runs publish
only when run on `main`. Use stable `v<version>` releases with Windows update assets
for this repository's latest release; iOS distribution continues through TestFlight.

The installer test uses the real NSIS updater with a local feed: a bad checksum
must fail, then the genuine installer downloads successfully without forcing a
restart. Reinstallation also verifies tasks/preferences and retained planner data.

Builds are unsigned unless the signing credentials below are configured. A direct
installer needs a trusted code-signing certificate or cloud signing service.
For new signing infrastructure, use a hardware-backed or managed signing service
(such as Microsoft Artifact Signing); wire its supported signing integration into
CI rather than committing private keys. The existing `CSC_LINK`/`CSC_KEY_PASSWORD`
hooks support compatible certificate-based signing. An MSIX distribution through
the Microsoft Store instead uses Store package signing and Store-managed updates.

## Connect iPhone

Open **Settings → Account**, create an account, confirm the email, then sign in.
In iOS, open **Settings → Account** and use the same credentials.
Existing local items are added to that account. The local planner stays bound to
its original account after sign-out to avoid mixing account data. Sign-out keeps
local records and disconnects sync.

Changes save first, then upload. Desktop subscribes to Realtime and both apps
catch up every eight seconds while active. Conflicts show a version comparison
in Settings. Sessions use Windows safeStorage encryption; the renderer cannot
read credentials or access Node. Only a publishable Supabase key is bundled.

## Desktop

- **Ctrl+N** quick add, **Ctrl+1–6** pages, **Ctrl+F** search lists, **Ctrl+/** all shortcuts.
  On a focused item, **E** edits and **Delete** deletes.
- Quick add from anywhere with **Ctrl+Shift+Space** (changeable in Settings). Closing
  the window keeps Orbit in the tray so reminders still arrive; quit from the tray.
- Task and habit reminders show as Windows notifications. Turn them off in Settings.
- **Settings → Import & Export** writes a JSON backup (readable by iPhone too) or a
  CSV of tasks. Importing shows what would be added or changed first.

## Scope

Task notes, dates, times, durations, completion and list assignment are editable.
Existing iOS tags, subtasks and reminder offsets survive edits, but Windows has no
editors for them yet. Drag rescheduling and background service sync remain follow-up work.
