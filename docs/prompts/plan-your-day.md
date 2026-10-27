# Prompt: design "Plan your day" for Orbit (AI-assisted)

The first version of **Plan this day** was removed in this release. It asked people to pick a day,
working hours, a writable calendar, items and durations before it would suggest anything, and it
only knew about Apple Calendar on iPhone. Use the prompt below with a design/research model (or a
designer) to rethink it before anything is rebuilt.

---

You are a senior product designer and engineer helping redesign the "Plan your day" feature of
**Orbit**, a calm, local-first planner for iPhone (SwiftUI, SwiftData) and Windows (Electron). Orbit
has Today (tasks dated today, overdue tasks and habits due today), Calendar, Notes, Habits and
Settings. Tasks can have a day, an optional time and a duration (default 30 minutes), and can be
tracked as "in progress" with an optional focus timer. Habits repeat daily, on weekdays, on
weekends or weekly, with a target count. Sync is optional; many people use Orbit without an account.

**The job:** in under a minute each morning (or the night before), help a person turn "everything
I could do" into "a realistic day", and keep that plan honest as the day changes.

**Design a feature that answers these questions explicitly:**

1. **Where does the person's schedule come from?**
   - Apple Calendar via EventKit on iPhone (already connected for reading), Google/Outlook on Windows
     (no integration exists yet; propose OAuth vs. ICS subscription vs. none).
   - **What if their commitments are not in any calendar?** (Shift workers, students, parents, people
     who keep it in their head.) Propose low-effort capture: a typical-week template ("weekdays
     9–5 at work, kids 3:30–7"), a one-tap "I'm busy until…" control, learning from when tasks are
     actually completed, or simply asking "What's fixed today?" in plain language and parsing it
     with Orbit's quick-add grammar (`gym 6pm`, `work 9-5`).
   - How to treat all-day events, tentative/free events, travel, and time-zone changes.
2. **What does the AI do, and what stays deterministic?** Separate (a) a deterministic scheduler
   that packs items into free gaps (Orbit already has one: `ios/Shared/DailyPlanning.swift`) from
   (b) an optional model that estimates durations, orders by energy and urgency, explains its
   choices, and turns a messy brain-dump or a long note into tasks. The plan must be correct with
   the AI turned off.
3. **Privacy and cost.** Orbit's promise is local-first and "no personal text leaves the device for
   coaching". Compare on-device models (Apple Foundation Models / Core ML on iOS, a small local model
   on Windows) with an opt-in cloud model. Specify exactly what data would be sent, when, and the
   consent copy. Orbit is free; say how cloud inference would be paid for, or avoid it.
4. **Interaction.** Sketch the flow: entry point (Today's plan card? a morning prompt? the agenda's
   Day/Week view?), the proposal screen, editing (drag to reorder, nudge times, "not today"),
   accepting, and what happens when the day slips (re-plan the afternoon in one tap, roll unfinished
   items to tomorrow or Someday). Keep it calm: no nagging, no streak guilt.
5. **Output.** Does accepting a plan write calendar events, set task times in Orbit, or both? How are
   edits in the calendar reflected back? How does it behave with no calendar at all?
6. **Habits.** How habits with a count (drink water ×6) or a weekly target fit into a day without
   becoming rigid time blocks.
7. **Success measures.** Propose 3 measurable signals (e.g. share of planned items completed, time
   to accept a plan, re-plans per day) that can be computed locally.

**Deliver:** (1) a one-paragraph product principle, (2) the end-to-end flow as numbered steps with
screen-by-screen copy for iPhone and Windows, (3) the data model changes, (4) the algorithm and the
exact model prompt/inputs/outputs if a model is used, (5) edge cases and failure states, (6) a
staged rollout (v1 without AI, v2 with on-device AI, v3 optional cloud), and (7) open questions to
test with five real users.

Constraints: match Orbit's existing visual language (dark/light, coral/sage/lavender/honey accents,
rounded quiet cards), respect Dynamic Type and keyboard use, and never schedule anything without
the person reviewing it first.
