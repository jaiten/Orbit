const { test } = require("node:test");
const assert = require("node:assert/strict");
const { announceRelease } = require("../scripts/announce-release.cjs");

test("a published release is broadcast on the public release channel", async () => {
  let sent;
  await announceRelease({
    version: "1.2.3",
    url: "https://example.supabase.co",
    key: "publishable",
    fetch: async (url, options) => {
      sent = { url: String(url), options };
      return { ok: true, status: 202 };
    },
  });
  assert.equal(sent.url, "https://example.supabase.co/realtime/v1/api/broadcast");
  assert.equal(sent.options.headers.apikey, "publishable");
  assert.deepEqual(JSON.parse(sent.options.body), {
    messages: [{ topic: "orbit-releases", event: "release", payload: { version: "1.2.3" } }],
  });
  await assert.rejects(announceRelease({ version: "latest", fetch: async () => ({ ok: true }) }), /Invalid/);
  await assert.rejects(
    announceRelease({
      version: "1.2.3",
      url: "https://example.supabase.co",
      key: "k",
      fetch: async () => ({ ok: false, status: 401 }),
    }),
    /401/,
  );
});
