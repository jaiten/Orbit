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
