# Orbit for Windows

A dedicated Electron planner with a two-column Today view, lists, a seven-day view,
task/habit editing, recurring tasks, history, and sync. Quick-add understands phrases
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
The portable executable is `dist/Orbit-0.2.0.exe`. Windows CI uploads it as the
`Orbit-Windows` artifact. This build is unsigned; Windows may show a publisher
warning. Code signing and automatic updates are not configured.

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

## Scope

Task notes, priorities, dates/times, durations, completion, and daily/weekly/monthly
recurrence and list assignment are editable. Lists can be created and renamed.
Existing iOS tags, subtasks and reminder values
survive edits, but their dedicated Windows editors are not included yet. Windows
notification scheduling, drag rescheduling, custom RRULEs, background service sync,
and account recovery UI remain follow-up work.
