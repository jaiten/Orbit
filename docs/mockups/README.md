# Design reference

The look of both apps follows the app screens on the Orbit website
([jaiten/orbit-web](https://github.com/jaiten/orbit-web): `src/components/devices/*`,
`src/components/widgets/Widgets.tsx`, `src/components/bklit/*`, `src/lib/motion.ts`).
Colours, type, row metrics, grid shape and springs live in `shared/design-tokens.json`,
which generates `windows/ui/tokens.css` and `ios/Shared/DesignTokens.swift`.

The rules, in short:

- Canvas `#F5F5F7` / `#141416`; cards and rows on `#FFFFFF` / `#1F1F21` with a 1px line
  (`#E4E4E8` / `#323236`) instead of a shadow. Cards 18px radius, rows 12px, chips pill.
- Large title 34–36 bold with tight tracking; 11px uppercase eyebrows (+0.1em) above cards
  and sections; tabular numerals for counts and times.
- Coral `#E87359` only for ticks, progress, selection and the one primary action (text
  `#B74F38` in light mode). Habit colours appear only as dots, grid boxes and bars.
- Springs (stiffness 300, damping 30) for UI, softer for large elements; opacity and
  transform only; rows enter 50ms apart; reduced motion turns movement into fades.

## Screens

`windows-*.png` and `ios-today.png` are the apps as they look now, with the website's
sample plan. `comparisons/` shows each screen as website · before · after.

## Notes (October 2026)

`notes/notes-concept.png` (from `notes/notes-concept.html`) is the Notion-like direction for
Notes in Orbit's colours: a growing add field that turns long text into a note, sections as
toggles with pages in quiet cards, and a page with an icon, large title and properties. Screens
3–4 (blocks, a `/` menu, checklist lines that become tasks) are concepts, not built.
`notes/windows-*.png` are screenshots of the Windows build from this change.

## Beta interface direction (30 October 2026)

`beta-interface.png` is a generated design proposal reflecting the latest feedback:
retain the Windows sidebar, compact habits, optional progress panels with Overall
progress off by default, per-task anytime rows and hover-only calendar drag grips.
The iOS note toolbar uses monochrome list, indent, undo/redo and Done controls.
The subsequent implementation uses a single 12px radius for Windows content
cards, task rows, fields, menus and compact habit rows with colour dots. The
sidebar retains its existing shape. Panels move
between columns or above the task list in Edit layout; drag the divider to resize
columns. Unchecked panels stay hidden while arranging. Overall progress follows
the selected accent. Recent progress always shows seven days; selecting one opens
that day to review or correct tasks, and returning to Today restores the current day.
Past habit check-ins are corrected in History; the Today screen only logs the
current day. Progress rings have no selection checkmarks or letter underlines.
Overall progress uses compact, unnumbered cells and is hidden by default.

This board is a design reference; device validation and release evidence are
described in the beta checklist.

## Latest surface refinements (30 October 2026)

Windows uses a lighter charcoal canvas, subtle card borders and compact plan
spacing. Overall progress has small, unnumbered cells in the selected accent,
with its range aligned to the right. The update icon stays hidden until a newer
version is available. Habit history uses compact horizontal twelve-week grids.

iOS note icons can be chosen from twenty symbols; the choice is included in sync
and portable backups. Tasks uses the shared search surface. Note cards clip the
swipe background to their rounded edges, including short title-only pages, and
the note background fills the keyboard safe area.
