# Shared test cases

Both apps run these files, so the rules stay identical on iPhone and Windows:

| File | Windows test | iOS test |
| --- | --- | --- |
| `habits.json` | `windows/tests/habits.test.cjs` | `SharedCaseTests.testHabitCases` |
| `consistency.json` | `windows/tests/habits.test.cjs` | `SharedCaseTests.testConsistencyCases` |
| `today.json` | `windows/tests/today.test.cjs` | `SharedCaseTests.testTodayCases` |
| `quick-add.json` | `windows/tests/planning.test.cjs` | `SharedCaseTests.testQuickAddPhrases` |
| `export-sample.json` / `.csv` | `windows/tests/planner-tools.test.cjs` | `SharedCaseTests.testExportRoundTrip` |
| `notes.json` | `windows/tests/notes.test.cjs` | `SharedCaseTests.testNoteCases` |

The export sample is evaluated in UTC (the CSV time column is local time).
