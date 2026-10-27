// Notes: long captures become a titled page instead of a to-do.
// Mirrors ios/Shared/NoteRules.swift; cases in shared/test-cases/notes.json.
const OrbitNotes = (() => {
  /** Captures longer than this (or with a line break) become notes. */
  const THRESHOLD = 120;
  const TITLE_LIMIT = 60;

  const isNote = (text) => {
    const value = String(text ?? "").trim();
    return value.includes("\n") || value.length > THRESHOLD;
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

  return { THRESHOLD, isNote, split, snippet };
})();
if (typeof module !== "undefined") module.exports = OrbitNotes;
