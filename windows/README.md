# Windows client — phase 3

The first milestone is the native iOS UX prototype. There is no Windows executable
yet. This directory reserves the next client boundary; it is not a completed app.

Use an Electron desktop shell with SQLite persistence and a React UI after the iOS
design is validated. Share the Supabase wire schema and `shared/design-tokens.json`,
not the SwiftData database file. The intended views match iOS: Today, Plan (week and
month), Tasks, Habits, and You.

Implementation sequence:

1. SQLite migrations for the five core entities plus outbox and sync cursor tables.
2. Repository operations matching `ios/Shared/Mutations.swift`; preserve UUIDs,
   calendar-day habit keys, reminder arrays, subtasks, ordering, and recurrence IDs.
3. Context-isolated preload API with validated IPC; renderer has no Node access.
4. Today, editors, drag scheduling, weekly targets, heatmaps, and theme tokens.
5. Windows notification adapter and a single nearest-reminder scheduler.
6. Authenticated Supabase transport, reconnect catch-up, and conflict UI.
7. Windows installer and tests for offline restart, DST, duplicate delivery, and
   concurrent changes from iOS.

Do not claim native Windows parity or instant sync until those checks pass.
