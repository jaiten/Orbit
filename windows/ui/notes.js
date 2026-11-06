// Notes: long captures become a titled page instead of a to-do.
// Mirrors ios/Shared/NoteRules.swift; cases in shared/test-cases/notes.json.
const OrbitNotes = (() => {
  // IDs match iOS SF Symbols so the same choice travels with the note.
  // prettier-ignore
  const icons = [
    ["doc.text","Document","M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5M9 13h6M9 17h4"],
    ["book.closed","Book","M5 3h14v18H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM3 17h16M7 3v14"],
    ["pencil","Pencil","m15 5 4 4M4 20l4-1L20 7a2.8 2.8 0 0 0-4-4L4 15z"],
    ["lightbulb","Idea","M9 18h6M10 21h4M8 14a6 6 0 1 1 8 0c-1 1-1 2-1 2H9s0-1-1-2z"],
    ["star","Star","m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9z"],
    ["heart","Heart","M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8z"],
    ["bookmark","Bookmark","M6 3h12v18l-6-4-6 4z"],
    ["flag","Flag","M4 22V3m0 1c5-4 11 4 16 0v11c-5 4-11-4-16 0"],
    ["calendar","Calendar","M5 5h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM16 3v4M8 3v4M3 11h18M8 15h2M14 15h2"],
    ["checklist","Checklist","m3 6 2 2 3-4M11 6h10M3 13l2 2 3-4M11 13h10M3 20l2 2 3-4M11 20h10"],
    ["briefcase","Work","M3 7h18v14H3zM8 7V3h8v4M3 12c6 4 12 4 18 0M10 12h4v4h-4z"],
    ["house","Home","m3 11 9-8 9 8M5 9v12h14V9M9 21v-8h6v8"],
    ["leaf","Leaf","M20 3C9 2 2 8 5 15s14 8 15-12zM3 22 15 10"],
    ["sun.max","Sun","M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5 19 19M5 19l1.5-1.5M17.5 6.5 19 5"],
    ["moon","Moon","M21 13a9 9 0 1 1-10-10 7 7 0 0 0 10 10z"],
    ["cup.and.saucer","Coffee","M3 8h14v6a6 6 0 0 1-12 0V8M17 9h2a3 3 0 0 1 0 6h-2M2 22h18M7 2v3M12 2v3"],
    ["airplane","Travel","m22 2-7 20-4-9-9-4zM11 13 22 2"],
    ["map","Map","m3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2zM9 3v16M15 5v16"],
    ["music.note","Music","M9 18V5l12-2v13M9 5v4l12-2M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0M21 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0"],
    ["gift","Gift","M3 8h18v4H3zM5 12v9h14v-9M12 8v13M12 8H8a3 3 0 1 1 3-3zm0 0h4a3 3 0 1 0-3-3z"],
    ["camera","Camera","M3 7h4l2-3h6l2 3h4v14H3zM16 13a4 4 0 1 1-8 0 4 4 0 0 1 8 0"],
    ["globe","Globe","M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18"],
    ["flame","Fire","M12 2c1 5-5 6-5 11a5 5 0 0 0 10 0c0-2-1-4-2-5 0 3-2 3-2 3 1-4 0-6-1-9z"],
    ["paintpalette","Art","M12 3a9 9 0 1 0 0 18h1a2 2 0 0 0 0-4h-1a2 2 0 0 1 0-4h5a4 4 0 0 0 4-4c0-4-5-6-9-6zM7 8h.01M11 6h.01M16 7h.01M6 13h.01"],
  ].map(([id, name, path]) => ({ id, name, path }));
  const resolveIcon = (value) => icons.find((choice) => choice.id === value) || icons[0];

  /**
   * Captures longer than THRESHOLD characters, with more than WORD_LIMIT words, or with a line break
   * become notes. Date and time words ("on friday at 6pm") don't count: they belong to a task.
   */
  const THRESHOLD = 120;
  const WORD_LIMIT = 8;
  const TITLE_LIMIT = 60;
  const WHEN_WORD =
    /^(today|tonight|tomorrow|tmrw|tmr|yesterday|mon|monday|tue|tues|tuesday|wed|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday|sun|sunday|next|this|at|on|by|before|every|daily|weekly|morning|afternoon|evening|noon|midnight|am|pm|\d{1,2}(:\d{2})?(am|pm)?)[.,!?]?$/i;
  const countedWords = (value) => value.split(/\s+/).filter((word) => word && !WHEN_WORD.test(word)).length;

  const isNote = (text) => {
    const value = String(text ?? "").trim();
    return value.includes("\n") || value.length > THRESHOLD || countedWords(value) > WORD_LIMIT;
  };

  /** Splits captured text into { title, body }: the first line, the first short sentence, or the opening words. */
  function split(text) {
    const value = String(text ?? "")
      .replace(/\r\n?/g, "\n")
      .trim();
    const lines = value.split("\n");
    if (lines.length > 1) return { title: lines[0].trim(), body: lines.slice(1).join("\n").trim() };
    const sentence = value.match(/^(.+?[.!?])\s+(\S[\s\S]*)$/);
    if (sentence && sentence[1].length <= 80)
      return { title: sentence[1].replace(/\.$/, ""), body: sentence[2].trim() };
    if (value.length <= TITLE_LIMIT) return { title: value, body: "" };
    let title = "";
    for (const word of value.split(/\s+/)) {
      if (title && (title + " " + word).length > TITLE_LIMIT) break;
      title = title ? title + " " + word : word.slice(0, TITLE_LIMIT);
    }
    return { title: title + "…", body: value };
  }

  /** One line under a note's title: the start of its body. */
  const snippet = (body) =>
    String(body ?? "")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 140);

  return { THRESHOLD, WORD_LIMIT, isNote, split, snippet, icons, resolveIcon };
})();
if (typeof module !== "undefined") module.exports = OrbitNotes;
