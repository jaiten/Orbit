// The feel of finishing things: sounds, the day-complete moment, milestone badges and the accents they
// unlock. Badges come from synced data (rewards.js), so Windows and iPhone agree; what has already been
// celebrated is remembered on this PC so nothing is announced twice.

/** Short synthesised sounds (no files): a soft tick, a rising chime for a finished day, a sparkle for a badge. */
const OrbitSounds = (() => {
  let context = null;
  const enabled = () => localStorage.getItem("sounds") !== "off";
  const notes = {
    tick: [[1318.5, 0, 0.09, 0.06]],
    day: [
      [523.25, 0, 0.5, 0.07],
      [659.25, 0.09, 0.5, 0.07],
      [783.99, 0.18, 0.6, 0.07],
      [1046.5, 0.3, 0.9, 0.06],
    ],
    badge: [
      [880, 0, 0.35, 0.06],
      [1318.5, 0.1, 0.6, 0.06],
    ],
  };
  function play(kind) {
    if (!enabled() || !notes[kind]) return;
    try {
      context ??= new AudioContext();
      const start = context.currentTime + 0.01;
      for (const [frequency, at, length, volume] of notes[kind]) {
        const tone = context.createOscillator(),
          gain = context.createGain();
        tone.type = "sine";
        tone.frequency.value = frequency;
        gain.gain.setValueAtTime(0, start + at);
        gain.gain.linearRampToValueAtTime(volume, start + at + 0.012);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + at + length);
        tone.connect(gain).connect(context.destination);
        tone.start(start + at);
        tone.stop(start + at + length + 0.05);
      }
    } catch {
      /* Audio can be unavailable; finishing things still works. */
    }
  }
  return { play, enabled };
})();

/** A burst of confetti in the accent and habit colours, for a finished day or a new badge. */
function confetti() {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const canvas = document.createElement("canvas");
  canvas.className = "confetti";
  canvas.width = innerWidth * devicePixelRatio;
  canvas.height = innerHeight * devicePixelRatio;
  document.body.append(canvas);
  const ink = canvas.getContext("2d");
  ink.scale(devicePixelRatio, devicePixelRatio);
  const style = getComputedStyle(document.documentElement);
  const colours = ["--accent", "--sage", "--lavender", "--honey", "--clay"].map((name) =>
    style.getPropertyValue(name).trim(),
  );
  const pieces = Array.from({ length: 90 }, () => ({
    x: innerWidth / 2 + (Math.random() - 0.5) * 160,
    y: innerHeight * 0.55,
    vx: (Math.random() - 0.5) * 9,
    vy: -6 - Math.random() * 8,
    size: 4 + Math.random() * 5,
    turn: Math.random() * Math.PI,
    spin: (Math.random() - 0.5) * 0.3,
    colour: colours[Math.floor(Math.random() * colours.length)] || "#e87359",
  }));
  const started = performance.now();
  const frame = (now) => {
    const age = now - started;
    ink.clearRect(0, 0, innerWidth, innerHeight);
    for (const piece of pieces) {
      piece.vy += 0.28;
      piece.vx *= 0.99;
      piece.x += piece.vx;
      piece.y += piece.vy;
      piece.turn += piece.spin;
      ink.save();
      ink.globalAlpha = Math.max(0, 1 - age / 1800);
      ink.translate(piece.x, piece.y);
      ink.rotate(piece.turn);
      ink.fillStyle = piece.colour;
      ink.fillRect(-piece.size / 2, -piece.size / 4, piece.size, piece.size / 2);
      ink.restore();
    }
    if (age < 1800) requestAnimationFrame(frame);
    else canvas.remove();
  };
  requestAnimationFrame(frame);
}

/** The note above the writing bar (shared with streak milestones). */
let momentTimer;
function showMoment(title, text, { colour = "", big = false } = {}) {
  const box = $("#celebration");
  if (!box) return;
  box.innerHTML = `<span class="celebration-burst ${colour ? "fill-" + colour : ""}" aria-hidden="true"></span><strong>${esc(title)}</strong><span>${esc(text)}</span>`;
  box.classList.toggle("big", big);
  box.hidden = false;
  box.classList.remove("show");
  void box.offsetWidth;
  box.classList.add("show");
  clearTimeout(momentTimer);
  momentTimer = setTimeout(() => (box.hidden = true), big ? 5000 : 4000);
}

/** Today's plan: tasks for today (not notes) and habits due today, and how many are done. */
function todayProgress() {
  const day = today();
  const tasks = rows("tasks").filter((t) => !t.isNote && OrbitPlanner.onDay(planItem(t), day, day));
  const habits = rows("habits").filter((h) => (!h.createdAt || plannerDay(h.createdAt) <= day) && dueOn(h));
  return {
    total: tasks.length + habits.length,
    done: tasks.filter((t) => t.completedAt).length + habits.filter((h) => checked(h)).length,
  };
}
const rewardValues = () =>
  OrbitRewards.metrics(
    rows("tasks").map((t) => ({ completedDay: t.completedAt ? plannerDay(t.completedAt) : null, isNote: t.isNote })),
    rows("habit_logs"),
  );
const readSet = (key) => {
  try {
    return new Set(JSON.parse(localStorage.getItem(key) || "null") || []);
  } catch {
    return new Set();
  }
};
/** Badges earned so far: from the data, plus any celebrated before (so an accent never locks again). */
function earnedBadges() {
  return [...new Set([...readSet("earnedBadges"), ...OrbitRewards.earned(rewardValues())])];
}
/** Accents you can pick now. */
const availableAccents = () => OrbitRewards.accents(earnedBadges());

/** Called when something is checked off here (not undone): a soft tick, and celebrations may follow. */
let lastLocalCompletion = 0;
function noteCompletion() {
  lastLocalCompletion = Date.now();
  OrbitSounds.play("tick");
}

/**
 * After each load: new badges and a newly finished day are celebrated, but only right after something
 * was finished on this PC; changes arriving from another device are recorded quietly.
 */
let rewardsReady = false,
  dayWasComplete = false;
function checkRewards() {
  const earned = OrbitRewards.earned(rewardValues());
  const seen = readSet("earnedBadges");
  const fresh = earned.filter((id) => !seen.has(id));
  const progress = todayProgress();
  const dayComplete = progress.total > 0 && progress.done === progress.total;
  const local = Date.now() - lastLocalCompletion < 5000;
  if (rewardsReady && local) {
    if (dayComplete && !dayWasComplete && localStorage.getItem("dayCompleteShown") !== today()) {
      localStorage.setItem("dayCompleteShown", today());
      setTimeout(() => {
        OrbitSounds.play("day");
        confetti();
        showMoment("Day complete", `All ${progress.total} done. Nice work.`, { big: true });
      }, 350);
    } else if (fresh.length) {
      const badge = OrbitRewards.data.badges.find((b) => b.id === fresh.at(-1));
      setTimeout(() => {
        OrbitSounds.play("badge");
        confetti();
        showMoment(
          `Badge: ${badge.title}`,
          badge.unlocks ? `${badge.unlocks[0].toUpperCase() + badge.unlocks.slice(1)} accent unlocked` : badge.detail,
          { big: true },
        );
      }, 350);
    }
  }
  if (rewardsReady && local) void offerEveningCheckIn();
  if (fresh.length || !rewardsReady)
    localStorage.setItem("earnedBadges", JSON.stringify([...new Set([...seen, ...earned])]));
  dayWasComplete = dayComplete;
  rewardsReady = true;
}

/** Settings → Milestones: every badge, earned or with its progress, and what it unlocks. */
function milestonesSection() {
  const have = new Set(earnedBadges());
  const values = rewardValues();
  const cards = OrbitRewards.progress(values)
    .map((badge) => {
      const done = have.has(badge.id);
      const reward = badge.unlocks ? `Unlocks ${badge.unlocks}` : "";
      const swatch = badge.unlocks
        ? `<i class="accent-swatch" data-swatch="${badge.unlocks}" aria-hidden="true"></i>`
        : "";
      return `<div class="badge-card ${done ? "earned" : ""}">
        <span class="badge-medal" aria-hidden="true">${done ? "★" : "☆"}</span>
        <span class="badge-text"><strong>${esc(badge.title)}</strong><small>${esc(badge.detail)}${reward ? ` · ${swatch}${esc(reward)}` : ""}</small>
        ${done ? "" : `<span class="badge-bar" role="progressbar" aria-label="${esc(badge.title)} progress" aria-valuemin="0" aria-valuemax="${badge.goal}" aria-valuenow="${badge.value}"><i data-progress="${badge.value / badge.goal}"></i></span>`}</span>
      </div>`;
    })
    .join("");
  return `<section class="settings-block" id="milestones"><h2>Milestones</h2>
    <p class="secondary">${values.completions} things done on ${values.activeDays} ${values.activeDays === 1 ? "day" : "days"}. Badges unlock new accent colours.</p>
    <div class="badge-grid">${cards}</div></section>`;
}
function bindMilestones() {
  document
    .querySelectorAll("[data-swatch]")
    .forEach((dot) => dot.style.setProperty("background", `var(--swatch-${dot.dataset.swatch})`));
  document
    .querySelectorAll(".badge-bar i[data-progress]")
    .forEach((bar) => (bar.style.width = `${Number(bar.dataset.progress) * 100}%`));
}

/**
 * After the first thing finished on this PC, a one-time offer of the evening check-in (off until
 * chosen): a reminder at 8 PM, only on days something is still left.
 */
async function offerEveningCheckIn() {
  if (localStorage.getItem("eveningOffered") || !api.desktopSettings) return;
  localStorage.setItem("eveningOffered", "yes");
  const settings = await api.desktopSettings().catch(() => null);
  if (!settings || settings.eveningCheckIn !== null || !settings.notifications) return;
  const card = document.createElement("div");
  card.className = "evening-offer";
  card.setAttribute("role", "dialog");
  card.setAttribute("aria-label", "Evening check-in");
  card.innerHTML = `<strong>Want a gentle evening check-in?</strong><span>At 8 PM, only if something is still left that day.</span>
    <div><button class="primary" data-evening="on">Turn on</button><button data-evening="off">Not now</button></div>`;
  document.body.append(card);
  card.querySelectorAll("[data-evening]").forEach(
    (button) =>
      (button.onclick = async () => {
        card.remove();
        if (button.dataset.evening === "on") {
          await api.desktopSettings({ eveningCheckIn: 20 * 60 }).catch(() => {});
          showMoment("Evening check-in on", "Change the time in Settings.");
        }
      }),
  );
}
