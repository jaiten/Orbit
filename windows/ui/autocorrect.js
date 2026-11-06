// Autocorrect as you type, like OneNote: when a word is finished (space, Return or punctuation), it is
// checked against apostrophe rules (dont → don't), common typos (teh → the), your own rules from
// Settings, and, for anything else Windows' spell checker flags, its first suggestion when that is a
// one-letter slip. Ctrl+Z right after takes a correction back.
const OrbitAutocorrect = (() => {
  // Words that only exist with an apostrophe. Ambiguous ones (its, were, well, ill, id, hell, lets,
  // shell, wed, hes) are left alone.
  // prettier-ignore
  const APOSTROPHES = Object.fromEntries([
    "aren't", "can't", "couldn't", "didn't", "doesn't", "don't", "hadn't", "hasn't", "haven't", "isn't",
    "mightn't", "mustn't", "needn't", "shouldn't", "wasn't", "weren't", "won't", "wouldn't", "ain't",
    "I'm", "I've", "you're", "you've", "you'll", "you'd", "they're", "they've", "they'll", "they'd",
    "we've", "she's", "that's", "that'll", "what's", "what're", "who's", "who'll",
    "who've", "where's", "there's", "there'll", "here's", "how's", "when's", "why's", "could've",
    "should've", "would've", "might've", "must've", "y'all", "o'clock", "it'll", "it'd",
  ].map((word) => [word.replace(/'/g, "").toLowerCase(), word]));
  // prettier-ignore
  const TYPOS = {
    teh: "the", adn: "and", nad: "and", taht: "that", thsi: "this", tihs: "this", hte: "the", jsut: "just",
    waht: "what", wiht: "with", whith: "with", wich: "which", becuase: "because", beacuse: "because",
    becasue: "because", thier: "their", recieve: "receive", recieved: "received", beleive: "believe",
    acheive: "achieve", seperate: "separate", definately: "definitely", definatly: "definitely",
    occured: "occurred", occurence: "occurrence", untill: "until", alot: "a lot", tommorow: "tomorrow",
    tomorow: "tomorrow", tommorrow: "tomorrow", calender: "calendar", enviroment: "environment",
    goverment: "government", freind: "friend", freinds: "friends", wierd: "weird", truely: "truly",
    neccessary: "necessary", necesary: "necessary", accomodate: "accommodate", occassion: "occasion",
    recomend: "recommend", reccomend: "recommend", existance: "existence", independant: "independent",
    concious: "conscious", embarass: "embarrass", garantee: "guarantee", happend: "happened",
    knowlege: "knowledge", noticable: "noticeable", persue: "pursue", posession: "possession",
    refered: "referred", relevent: "relevant", succesful: "successful", sucessful: "successful",
    suprise: "surprise", writting: "writing", begining: "beginning", buisness: "business",
    comming: "coming", diffrent: "different", finaly: "finally", foward: "forward", gaurd: "guard",
    immediatly: "immediately", interupt: "interrupt", libary: "library", mispell: "misspell",
    occuring: "occurring", peice: "piece", resturant: "restaurant", sentance: "sentence",
    shoudl: "should", similiar: "similar", tounge: "tongue", usualy: "usually", wednesay: "Wednesday",
    wensday: "Wednesday", febuary: "February",
  };
  const DEFAULTS = { enabled: true, apostrophes: true, spelling: true };
  const settings = () => {
    try {
      return { ...DEFAULTS, ...JSON.parse(localStorage.getItem("autocorrect") || "{}") };
    } catch {
      return { ...DEFAULTS };
    }
  };
  const saveSettings = (changes) => localStorage.setItem("autocorrect", JSON.stringify({ ...settings(), ...changes }));
  /** Your rules, one per line: "btw = by the way" (also -> or →). */
  function parseRules(text) {
    const rules = {};
    for (const line of String(text ?? "").split(/\r?\n/)) {
      const match = line.match(/^\s*(\S+)\s*(?:=|->|→)\s*(.+?)\s*$/);
      if (match) rules[match[1].toLowerCase()] = match[2];
    }
    return rules;
  }
  const customText = () => localStorage.getItem("autocorrectRules") || "";

  /** Keeps the typed capitals: Dont → Don't, DONT → DON'T, Teh → The. */
  function matchCase(typed, replacement) {
    if (typed.length > 1 && typed === typed.toUpperCase()) return replacement.toUpperCase();
    if (typed[0] === typed[0].toUpperCase()) return replacement[0].toUpperCase() + replacement.slice(1);
    return replacement;
  }
  /**
   * The correction for `word`, or null. `options` defaults to the saved settings; `rules` to the
   * saved custom rules. Pure apart from those defaults, so tests can call it directly.
   */
  function correct(word, options = settings(), rules = parseRules(customText())) {
    if (!options.enabled || !word || !/^[A-Za-z][A-Za-z']*$/.test(word)) return null;
    const key = word.toLowerCase();
    if (rules[key] !== undefined) return rules[key] === word ? null : rules[key];
    if (word === "i") return "I";
    if (options.apostrophes && APOSTROPHES[key] && !word.includes("'")) return matchCase(word, APOSTROPHES[key]);
    return TYPOS[key] ? matchCase(word, TYPOS[key]) : null;
  }

  /** Optimal string alignment distance: a swapped pair of letters counts as one slip. */
  function distance(a, b) {
    const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
    for (let j = 1; j <= b.length; j++) d[0][j] = j;
    for (let i = 1; i <= a.length; i++)
      for (let j = 1; j <= b.length; j++) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1;
        d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
        if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
          d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
      }
    return d[a.length][b.length];
  }
  /** The spell checker's fix, only when it is a single slip in a lowercase word of 4+ letters. */
  function spellingFix(word) {
    if (!settings().spelling || word.length < 4 || word !== word.toLowerCase()) return null;
    const result = globalThis.orbit?.spell?.(word);
    if (!result?.misspelled) return null;
    const best = result.suggestions?.[0];
    if (!best || /\s/.test(best) || best.toLowerCase() === word) return null;
    return distance(word, best.toLowerCase()) === 1 ? best : null;
  }

  const BOUNDARY = /^[\s.,!?;:)\]"]$/;
  const WORD_BEFORE = /([A-Za-z][A-Za-z']*)$/;
  /** Corrects the word before the caret in a textarea or input; `typed` is the boundary just typed. */
  function fixField(field, typed) {
    const end = field.selectionStart - typed.length;
    if (end < 1 || field.selectionStart !== field.selectionEnd) return;
    const match = field.value.slice(0, end).match(WORD_BEFORE);
    if (!match) return;
    const word = match[1].replace(/'+$/, "");
    const fix = correct(word) ?? spellingFix(word);
    if (!fix) return;
    const start = end - match[1].length;
    const caret = field.selectionStart;
    field.setSelectionRange(start, start + word.length);
    document.execCommand("insertText", false, fix);
    const next = caret + fix.length - word.length;
    field.setSelectionRange(next, next);
  }
  /** The same for a contenteditable page: works within the text node the caret is in. */
  function fixEditable(typed) {
    const selection = getSelection();
    if (!selection.rangeCount || !selection.isCollapsed) return;
    const node = selection.anchorNode,
      offset = selection.anchorOffset;
    if (node?.nodeType !== Node.TEXT_NODE) return;
    const end = offset - typed.length;
    if (end < 1) return;
    const match = node.textContent.slice(0, end).match(WORD_BEFORE);
    if (!match) return;
    const word = match[1].replace(/'+$/, "");
    const fix = correct(word) ?? spellingFix(word);
    if (!fix) return;
    const start = end - match[1].length;
    const range = document.createRange();
    range.setStart(node, start);
    range.setEnd(node, start + word.length);
    selection.removeAllRanges();
    selection.addRange(range);
    document.execCommand("insertText", false, fix);
    // insertText leaves the caret after the fix; step over the boundary that was typed.
    const after = getSelection();
    if (after.rangeCount && after.anchorNode?.nodeType === Node.TEXT_NODE) {
      const position = Math.min(after.anchorNode.textContent.length, after.anchorOffset + (offset - end));
      after.collapse(after.anchorNode, position);
    }
  }
  /** Turns autocorrect on for a text field or a contenteditable page. */
  function attach(element) {
    if (!element || element.dataset.autocorrect) return;
    element.dataset.autocorrect = "on";
    element.addEventListener("input", (event) => {
      if (!settings().enabled || event.isComposing) return;
      const typed =
        event.inputType === "insertText"
          ? event.data
          : event.inputType === "insertLineBreak" || event.inputType === "insertParagraph"
            ? "\n"
            : null;
      if (!typed || !BOUNDARY.test(typed)) return;
      if (element.isContentEditable) {
        // A new line moves the caret to another node; check the end of the line just left.
        if (typed === "\n") return;
        fixEditable(typed);
      } else fixField(element, typed);
    });
  }

  return { correct, parseRules, distance, settings, saveSettings, customText, attach, APOSTROPHES, TYPOS };
})();
if (typeof module !== "undefined") module.exports = OrbitAutocorrect;
