const { test } = require("node:test");
const assert = require("node:assert/strict");
const { place } = require("../ui/calendar-layout.js");
const progress = require("../ui/recent-progress.js");
test("timed tasks use separate lanes only while their intervals overlap", () => {
  const task = (id, time, durationMinutes) => ({
    id,
    dueDate: new Date(`2026-10-27T${time}:00`).getTime(),
    durationMinutes,
  });
  const blocks = place([
    task("a", "09:00", 90),
    task("b", "09:30", 30),
    task("c", "11:00", 60),
    task("late", "23:45", 60),
  ]);
  assert.deepEqual(
    blocks.map(({ task, lane, lanes }) => [task.id, lane, lanes]),
    [
      ["a", 0, 2],
      ["b", 1, 2],
      ["c", 0, 1],
      ["late", 0, 1],
    ],
  );
  assert.equal(blocks[0].start, 540);
  assert.equal(blocks.at(-1).end, 1440);
});
test("recent progress includes all scheduled habits and tasks, giving partial habit credit", () => {
  const result = progress.day(
    [
      { day: "2026-10-27", completedDay: "2026-10-27" },
      { day: "2026-10-27", completedDay: null },
      { day: "2026-10-27", isNote: true },
    ],
    [{ id: "h", frequencyRule: "DAILY", target: 2, createdDay: "2026-10-01" }],
    [{ habitID: "h", dayKey: "2026-10-27", count: 1 }],
    "2026-10-27",
  );
  assert.equal(result.ratio, 0.5);
  assert.equal(result.taskCount, 2);
  assert.equal(result.habitCount, 1);
  assert.equal(progress.day([], [], [], "2026-10-27").total, 0);
});

test("adjacent short events keep their minimum clickable cards from hiding one another", () => {
  const blocks = place(
    [0, 5, 10].map((minute) => ({
      dueDate: new Date(2026, 9, 27, 9, minute).getTime(),
      durationMinutes: 5,
    })),
  );
  assert.deepEqual(
    blocks.map(({ lane, lanes }) => [lane, lanes]),
    [
      [0, 3],
      [1, 3],
      [2, 3],
    ],
  );
});

test("progress preference excludes tasks and a late completion counts on one day", () => {
  const tasks = [{ day: "2026-10-26", completedDay: "2026-10-27" }];
  assert.equal(progress.day(tasks, [], [], "2026-10-26").total, 0);
  assert.equal(progress.day(tasks, [], [], "2026-10-27").ratio, 1);
  assert.equal(progress.day(tasks, [], [], "2026-10-27", false).total, 0);
});
