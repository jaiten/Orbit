// Web and email addresses in text: found, shown as links and opened in the browser or mail app.
// Notes draw them with a CSS highlight (no change to the text being edited); task titles wrap them in
// a span. Only http, https and mailto links are ever opened (see main.cjs "open-link").
(function (root) {
  // A URL: http(s)://… or www.…; an email address. Trailing punctuation is left out ("see x.com.").
  const PATTERN =
    /\b(?:https?:\/\/|www\.)[^\s<>"'`]+|\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b/gi;
  function trim(match) {
    let text = match;
    // Drop closing punctuation, and a closing bracket that has no opening one inside the link.
    for (;;) {
      const last = text.at(-1);
      if (/[.,;:!?'"]/.test(last)) text = text.slice(0, -1);
      else if (last === ")" && (text.match(/\(/g) || []).length < (text.match(/\)/g) || []).length)
        text = text.slice(0, -1);
      else if (last === "]" && !text.includes("[")) text = text.slice(0, -1);
      else break;
    }
    return text;
  }
  /** The address a piece of link text opens, or null. */
  function href(text) {
    if (/^https?:\/\//i.test(text)) return URL.canParse(text) ? text : null;
    if (/^www\./i.test(text)) return URL.canParse("https://" + text) ? "https://" + text : null;
    if (/^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$/.test(text)) return "mailto:" + text;
    return null;
  }
  /** Links in `text`: [{ start, end, text, url }] (UTF-16 offsets). */
  function find(text) {
    const result = [];
    for (const match of String(text ?? "").matchAll(PATTERN)) {
      const value = trim(match[0]);
      const url = href(value);
      if (url) result.push({ start: match.index, end: match.index + value.length, text: value, url });
    }
    return result;
  }
  const escape = (s) =>
    String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  /** Escaped HTML for `text` with each link in a span that opens it on click. */
  function html(text) {
    text = String(text ?? "");
    let out = "",
      at = 0;
    for (const link of find(text)) {
      out += escape(text.slice(at, link.start));
      out += `<span class="text-link" data-open-link="${escape(link.url)}" title="${escape(link.url)}">${escape(link.text)}</span>`;
      at = link.end;
    }
    return out + escape(text.slice(at));
  }
  const api = { find, href, html };
  if (typeof module === "object") module.exports = api;
  else root.OrbitLinks = api;
})(typeof window === "object" ? window : globalThis);
