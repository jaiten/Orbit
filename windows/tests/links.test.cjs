const { test } = require("node:test");
const assert = require("node:assert/strict");
const { find, html } = require("../ui/links.js");

test("links: web addresses, www and email, without trailing punctuation", () => {
  const text = "See https://example.com/a?b=1. Also www.orbit.app, (https://x.org/y) and me@site.co!";
  assert.deepEqual(
    find(text).map((l) => [l.text, l.url]),
    [
      ["https://example.com/a?b=1", "https://example.com/a?b=1"],
      ["www.orbit.app", "https://www.orbit.app"],
      ["https://x.org/y", "https://x.org/y"],
      ["me@site.co", "mailto:me@site.co"],
    ],
  );
  assert.deepEqual(
    find("Wikipedia https://en.wikipedia.org/wiki/Orbit_(film) done").map((l) => l.text),
    ["https://en.wikipedia.org/wiki/Orbit_(film)"],
  );
  assert.deepEqual(find("no links here, just 3.5 and a.b"), []);
});

test("links: task titles become escaped HTML with clickable spans", () => {
  assert.equal(
    html("Read <this> https://a.io"),
    'Read &lt;this&gt; <span class="text-link" data-open-link="https://a.io" title="https://a.io">https://a.io</span>',
  );
  assert.equal(html("plain"), "plain");
});
