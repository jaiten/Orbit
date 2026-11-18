# Tester bug fixes and platform audit — 18 November 2026

## Scope and confidence

Inspected `main` at `2ae155cfdf74491f92366fc60488a28c4cff8683`. This is a targeted source audit of editors, theme presentation, capture, authentication, calendar adapters, persistence, notification refresh, sync scheduling and Windows rendering. It is not a claim that every application path is bug free. Work belongs on a review branch; do not merge or publish until the remaining checks below pass.

The local host is Windows, Node 22.18.0. iOS cannot be compiled or run here. In particular, neither reported iOS blank-screen freeze has been reproduced on a simulator/device in this session. The changes remove suspect presentation/state paths and add reproduction coverage; those reports remain **pending iOS verification**, not established root causes.

## Reported issues

| Report | Change and evidence | Remaining verification |
| --- | --- | --- |
| Item color makes the app blank/frozen | Habit color now uses an explicit menu instead of a Form's automatic navigation picker. Habit editor population runs once, preserving the draft when it reappears. The same initialization protection covers task and detailed capture editors. Windows color-picker coverage passes in refinement smoke. | Run the new iOS color regression and repeat edits on a physical phone, including existing habits and counters. Capture a hang trace if the freeze persists. |
| Calendar address/location | Windows event editor reads/writes/clears locations. Google/Outlook adapters include locations on reads and PATCH bodies. Apple calendar snapshots and edit requests carry the field; omitted fields preserve old locations, explicit empty strings clear them. iOS event rows show the address; Apple's native event editor already offers location entry. | Real-account round trips for Apple, Google and Outlook; permissions and recurring occurrences. This is calendar-event support, not a new task-schema field. |
| Hours change but minutes do not | iOS task/capture time controls use wheel pickers with a direct capture binding that marks minute edits as explicit. One-time population prevents the draft resetting on return. Windows event inputs accept every minute instead of a five-minute step. Browser regression saves 09:37–10:43 successfully. | The exact original iOS failure is not reproduced locally. Run the new picker UI check, save/reopen, 12/24-hour clocks and DST boundary cases on iPhone. |
| Auth controls appear prematurely | User clarified: retain one form, disable actions until valid. Both platforms require a plausible email. Sign in requires a password; account creation requires at least eight characters; recovery needs only email. Windows also disables these actions during a request and when the backend is unavailable. Existing short passwords remain usable for sign in. | Real authentication-service acceptance is separate from these form checks. |
| Settings → close → reopen → appearance blanks screen | Replaced the iOS appearance popup with an in-place segmented control so a popup does not dismiss during a presentation appearance change. The settings sheet applies its selected scheme explicitly. UI regression repeats the reopen/change sequence and checks continued interaction. Windows reopen/theme sequence passes. | macOS CI and physical iPhone verification required; do not call the iOS freeze fixed solely from source inspection. |
| Chevron/plus outruns capture input | Removed the icon's separate 100 ms animation; it inherits the capture bar's focus transaction. | Observe keyboard dismissal and rapid focus changes on iPhone, with Reduce Motion and large text. Automated tests cannot establish perceived timing. |

## Additional findings and repairs

- **Lost calendar drafts on Windows:** the event dialog previously closed before persistence/provider success. It now stays open on failure, retaining the title, address and time for retry. Regression injects a failed write and retries successfully.
- **Silent calendar write failures on iOS:** `CalendarShare.apply` used `try?` and then republished the original event, clearing the requested edit. It now throws on failed EventKit writes or missing/unwritable event references. Sync reports the error and leaves the request pending. A missing-reference unit test covers failure reporting. A permanently missing event can require removing/replacing the pending request; a dedicated retry/discard UI is a follow-up.
- **Stale UI test assumptions:** refinement smoke expected month layout after earlier calendar interactions and read geometry during an asynchronous history refresh. It now explicitly selects Month and waits for the history chart to be visible.
- **Timezone test portability:** local Node's timezone database predates the 2026 Vancouver rule change. Tests now verify a stable historical instant and assert that the existing correction picks a zone with Windows' actual offset, including its old-database fallback. No production timezone behavior was changed.

## Validation

| Check | Local result |
| --- | --- |
| Windows unit tests | 198 passed, 0 failed |
| Windows lint/format | Passed |
| `npm run test:regressions` | Passed: reopened appearance, invalid/empty auth, location/minutes, failed calendar draft retention |
| `npm run test:refinements` | Passed, including habit colors, settings races, keyboard auth, planner/history flows |
| `npm run test:notes` | Passed |
| `npm run test:desktop` | Reached global-shortcut check, then failed: `Global shortcut not registered`. Registration is OS-wide and may conflict with another application; the cause is not established. Do not count the full suite as passed. |
| `npm run pack` | Passed: NSIS installer and portable executable generated locally; no publication |
| Update feed/checksum verification | Passed against local generated artifacts |
| Installer/update/reinstall smoke | Pending at report creation; see PR/check output for final result |
| iOS unit/UI/build | Not runnable locally; required macOS PR CI |
| Live services, physical devices, actual updater distribution | Not verified |

Added Swift tests for email validity, EventKit draft location/minute edits and failed calendar-reference reporting, plus iOS UI coverage for color, minute selection, settings reopen and empty auth. The new UI test is included in the default iOS smoke selection. Windows regression smoke is included in PR CI.

## Performance, race and error-handling follow-up

Prioritize measured work rather than changing animation durations indiscriminately. No before/after frame-time or memory improvement is claimed here.

1. **iOS full-history work on the main actor:** `SettingsView.AppearanceSection` queries all tasks, habits and logs and recomputes reward metrics in `body`. `NotificationScheduler.reminders` fetches all logs and repeatedly scans them across habits/days. `CalendarBridge.events` performs synchronous EventKit queries during consumers' view work. Cache/index aggregates by habit/day; constrain fetch windows; invalidate on relevant edits; profile populated planners in Instruments before and after. Preserve historical streak/reward semantics when bounding data.
2. **Notification replacement is reentrant:** `NotificationScheduler.replace` is an actor method but awaits system calls between reading/removing/adding notifications. Overlapping refreshes from edits, foreground and sync can interleave. Coalesce requests and serialize replacement with a latest-generation worker; test with delayed fake notification calls and competing snapshots before changing this path. Avoid cancelling valid scheduled reminders on partial failure.
3. **Windows full-store work:** `core.js.load` serializes every record to detect changes, and page rendering repeatedly filters logs through `rows`/`dailyCount`. Today already retains unchanged panels, which is useful. Add revision counters and per-habit/day indexes rather than rebuilding a full JSON signature; measure p50/p95 render and input latency with 500 tasks, 2,000+ logs and photos. Large DOM history/calendar views may benefit from windowing after profiling.
4. **Sync scheduling:** iOS already guards concurrent `run` calls with `busy/again`, Windows rejects stale reads with sequence/revision checks, and local mutations roll back persistence failures. Retain these safeguards. The iOS 20-second foreground poll still complements realtime/local-change triggers; add backoff on repeated failures and coalesce widget/reminder refreshes per committed batch. Verify account switches and widget/app simultaneous edits on actual devices.
5. **Global shortcuts:** startup currently ignores failure from `applyShortcut`. Surface an unavailable-shortcut status with an alternative choice; do not silently imply that quick add is registered. Local desktop smoke demonstrates why this needs an OS-aware test.
6. **Calendar edge cases:** Windows timed event editing currently reconstructs end time on the start day and rolls to the next day when necessary. Events lasting more than a day can be shortened; fixed 86,400,000 ms rollover also deserves DST coverage. Add an explicit timed end date and local calendar-day arithmetic in a focused follow-up, with overnight/multiday/DST tests.
7. **Dependency audit:** `npm ci`/`npm audit` reported six moderate findings in the development packaging dependency chain (minimatch/electron-builder family), no high/critical findings in that audit. Review the advisory paths and upgrade supported packaging dependencies in a dedicated PR; do not apply a forced downgrade automatically. This is not a full security audit.

## Acceptance before release

Require green macOS/iOS build and new UI checks, resolve or explain full desktop smoke, and perform physical iPhone checks for both freezes and capture motion. Verify real provider address add/edit/clear and minute persistence after relaunch/sync. Keep the PR in draft while these are outstanding. This work does not merge to `main`, bump release versions or claim TestFlight/Windows release publication.
