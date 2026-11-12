// Locked notes, locked sections and hidden sections.
//
// One password unlocks everything that is locked. It never leaves this PC: only a salted PBKDF2 hash is
// kept (in localStorage). Notes still sync as they always have; the lock keeps locked pages, and the
// pages of a locked section, out of view until the password is entered. Unlocking lasts until the
// window is minimised or hidden, or "Lock now" is chosen. iPhone uses Face ID or the passcode instead.
//
// A hidden section shows its pages without their titles or text in lists and search; opening a page
// shows it as usual.
const OrbitLocks = (() => {
  const KEY = "notesLock";
  const ITERATIONS = 210000;
  let unlocked = false;

  const stored = () => {
    try {
      return JSON.parse(localStorage.getItem(KEY) || "null");
    } catch {
      return null;
    }
  };
  const hasPassword = () => !!stored()?.hash;
  const hex = (bytes) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
  async function derive(password, salt, iterations = ITERATIONS) {
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, [
      "deriveBits",
    ]);
    const bits = await crypto.subtle.deriveBits(
      { name: "PBKDF2", hash: "SHA-256", salt: new TextEncoder().encode(salt), iterations },
      key,
      256,
    );
    return hex(bits);
  }
  async function setPassword(password) {
    const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
    localStorage.setItem(KEY, JSON.stringify({ salt, iterations: ITERATIONS, hash: await derive(password, salt) }));
    unlocked = true;
  }
  async function check(password) {
    const saved = stored();
    if (!saved?.hash) return false;
    return (await derive(password, saved.salt, saved.iterations || ITERATIONS)) === saved.hash;
  }

  const list = (id) => (id ? rows("lists").find((l) => l.id === id) : null);
  /** Whether a note sits behind the password: locked itself, or in a locked section. */
  const isLocked = (note) => !!note && (note.locked === true || list(note.listID)?.locked === true);
  /** Locked and not yet unlocked this session. */
  const isSealed = (note) => isLocked(note) && !unlocked;
  const sectionSealed = (id) => list(id)?.locked === true && !unlocked;
  /** A page in a hidden section: no title or text in lists and search. */
  const isHidden = (note) => !!note && list(note.listID)?.hidden === true;
  const anyLocks = () => rows("tasks").some((t) => t.isNote && t.locked) || rows("lists").some((l) => l.locked);

  /** Locks again. An open locked page is saved and swapped for a blank page to write on. */
  function lockNow() {
    if (!unlocked) return;
    if (page === "note" && isLocked(rows("tasks").find((t) => t.id === noteID))) {
      void saveNote().then(() => {
        unlocked = false;
        if (page === "note" && isLocked(rows("tasks").find((t) => t.id === noteID))) openNote(null);
        else render();
      });
      return;
    }
    unlocked = false;
    if (["note", "lists"].includes(page)) render();
  }
  // Minimising or hiding the window locks again.
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) lockNow();
  });

  /**
   * Asks for the password (or to create one, when none is set). Resolves true once unlocked; false if
   * cancelled. `mode` "change" asks for the current password, then a new one.
   */
  function prompt({ mode = hasPassword() ? "unlock" : "create", reason = "" } = {}) {
    let dialog = $("#lock-dialog");
    if (!dialog) {
      dialog = document.createElement("dialog");
      dialog.id = "lock-dialog";
      dialog.className = "lock-dialog";
      dialog.setAttribute("aria-labelledby", "lock-dialog-title");
      document.body.append(dialog);
    }
    const creating = mode === "create" || mode === "new";
    const title = { create: "Set a notes password", unlock: "Unlock notes", change: "Change notes password" }[
      mode === "new" ? "change" : mode
    ];
    dialog.innerHTML = `<form method="dialog" class="lock-form">
      <svg class="ui-icon lock-glyph" viewBox="0 0 24 24" aria-hidden="true"><path d="${LOCK_PATH}"/></svg>
      <h2 id="lock-dialog-title">${title}</h2>
      <p class="secondary">${esc(
        reason ||
          (creating
            ? "One password locks every locked note and section on this PC. It can't be recovered, so choose one you'll remember."
            : "Enter your notes password."),
      )}</p>
      <input type="password" name="password" aria-label="${creating ? "New password" : "Password"}" placeholder="${creating ? "New password" : "Password"}" autocomplete="${creating ? "new-password" : "current-password"}" required />
      ${creating ? '<input type="password" name="confirm" aria-label="Confirm password" placeholder="Confirm password" autocomplete="new-password" required />' : ""}
      <p class="lock-error" role="alert"></p>
      <footer><button type="button" data-lock-cancel>Cancel</button><button type="submit" class="primary">${creating ? "Set password" : mode === "change" ? "Next" : "Unlock"}</button></footer>
    </form>`;
    const form = dialog.querySelector("form"),
      error = dialog.querySelector(".lock-error");
    return new Promise((resolve) => {
      let result = false;
      dialog.querySelector("[data-lock-cancel]").onclick = () => dialog.close();
      dialog.addEventListener("close", () => resolve(result), { once: true });
      form.onsubmit = async (event) => {
        event.preventDefault();
        const password = form.elements.password.value;
        if (creating) {
          if (password.length < 4) return (error.textContent = "Use at least 4 characters.");
          if (password !== form.elements.confirm.value) return (error.textContent = "The passwords don't match.");
          await setPassword(password);
          result = true;
          dialog.close();
          return;
        }
        if (!(await check(password))) {
          error.textContent = "That password isn't right.";
          form.elements.password.select();
          dialog
            .querySelector(".lock-form")
            .animate(
              [
                { transform: "translateX(0)" },
                { transform: "translateX(-6px)" },
                { transform: "translateX(6px)" },
                { transform: "translateX(0)" },
              ],
              { duration: 220 },
            );
          return;
        }
        if (mode === "change") {
          dialog.close();
          result = await prompt({ mode: "new", reason: "Choose a new password." });
          return;
        }
        unlocked = true;
        result = true;
        dialog.close();
      };
      openDialog(dialog);
      form.elements.password.focus();
    });
  }
  /** Resolves true when locked content may be shown: already unlocked, or the password was entered. */
  const unlock = async (reason) => unlocked || (await prompt({ reason }));
  /** Before locking something, make sure a password exists (creating one if needed). */
  const ensurePassword = async () => hasPassword() || (await prompt({ mode: "create" }));

  return {
    isLocked,
    isSealed,
    isHidden,
    sectionSealed,
    hasPassword,
    anyLocks,
    unlock,
    ensurePassword,
    lockNow,
    changePassword: () => prompt({ mode: hasPassword() ? "change" : "create" }),
    get unlocked() {
      return unlocked;
    },
  };
})();
const LOCK_PATH = "M6 11h12v10H6zM8 11V7a4 4 0 0 1 8 0v4";
const UNLOCK_PATH = "M6 11h12v10H6zM8 11V7a4 4 0 0 1 7.5-2";

/** Lock / Remove lock for a note, for its menus. */
function lockEntries(note) {
  if (!note) return [];
  const own = note.locked === true;
  return [
    [
      own ? "Remove lock" : "Lock note",
      async () => {
        if (
          own
            ? !(await OrbitLocks.unlock("Enter your password to remove this lock."))
            : !(await OrbitLocks.ensurePassword())
        )
          return;
        if (page === "note" && noteID === note.id) await saveNote();
        const current = rows("tasks").find((t) => t.id === note.id) || note;
        await action(() => put("tasks", { ...clean(current), locked: own ? null : true, updatedAt: Date.now() }));
      },
    ],
  ];
}
/** Lock / hide choices for a note section's menu. */
function sectionLockEntries(id) {
  const section = rows("lists").find((l) => l.id === id);
  if (!section) return [];
  const save = (change) => action(() => put("lists", { ...clean(section), ...change, updatedAt: Date.now() }));
  return [
    [
      section.locked ? "Unlock section" : "Lock section",
      async () => {
        if (
          section.locked
            ? !(await OrbitLocks.unlock("Enter your password to unlock this section."))
            : !(await OrbitLocks.ensurePassword())
        )
          return;
        await save({ locked: section.locked ? null : true });
      },
    ],
    [section.hidden ? "Show titles" : "Hide titles", () => save({ hidden: section.hidden ? null : true })],
  ];
}
/** "Move to section" for a note's menus: General (no section), each note section, then Someday. As on iOS. */
/** Moves a note to a section (null: no section). Saves an open page first. */
async function moveNoteTo(id, listID) {
  if (page === "note" && noteID === id) await saveNote();
  const current = rows("tasks").find((t) => t.id === id);
  if (!current || (current.listID || null) === listID) return;
  await action(() => put("tasks", { ...clean(current), listID, updatedAt: Date.now() }));
}
function noteMoveEntry(note) {
  const move = (listID) => moveNoteTo(note.id, listID);
  const here = note.listID || null;
  const choices = [[null, "General"], ...orderedLists("notes").map((l) => [l.id, l.name]), [SOMEDAY, "Someday"]];
  return ["Move to section", null, choices.map(([id, name]) => [id === here ? `${name} ✓` : name, () => move(id)])];
}
/** Opens a note's page as a task (from right-click), unlocking first if needed. */
async function noteMenuToTask(note) {
  if (OrbitLocks.isSealed(note) && !(await OrbitLocks.unlock())) return;
  if (page === "note" && noteID === note.id) await saveNote();
  const current = rows("tasks").find((t) => t.id === note.id) || note;
  await action(async () => {
    await put("tasks", noteToTask(current));
    pendingNotes.delete(current.id);
    if (lastNoteID === current.id) {
      lastNoteID = null;
      localStorage.removeItem("lastNoteID");
    }
    if (noteID === current.id) {
      noteID = null;
      page = "lists";
    }
  });
}
