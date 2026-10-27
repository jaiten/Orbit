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
shortcuts, and provides an uninstaller. Run a newer installer to upgrade Orbit.
The app ID and user-data location are shared with the portable build, so upgrades
keep the local planner, preferences and sign-in data. Uninstalling keeps app data.
Automatic update checks and background downloads are not configured yet.

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
editors for them yet. Drag rescheduling, background service sync and automatic
updates remain follow-up work.
