const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  CalendarAccounts,
  googleEvent,
  microsoftEvent,
  microsoftBody,
  googleBody,
} = require("../calendar-accounts.cjs");

const json = (value, status = 200) => ({ ok: status < 400, status, json: async () => value });
const jwt = (claims) => `x.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.y`;

/** A stand-in Google: token endpoint, calendar list, events, and a log of every request. */
function fakeGoogle() {
  const calls = [];
  const fetch = async (url, options = {}) => {
    const href = String(url);
    calls.push({ url: href, method: options.method || "GET", body: options.body, headers: options.headers });
    if (href.includes("/token")) {
      const body = new URLSearchParams(String(options.body));
      if (body.get("grant_type") === "authorization_code") {
        assert.equal(body.get("code"), "the-code");
        assert.ok(body.get("code_verifier").length >= 43);
        return json({
          access_token: "access-1",
          refresh_token: "refresh-1",
          expires_in: 3600,
          id_token: jwt({ email: "me@gmail.com" }),
        });
      }
      return json({ access_token: "access-2", expires_in: 3600 });
    }
    if (href.includes("/calendarList"))
      return json({
        items: [
          { id: "me@gmail.com", summary: "Me", backgroundColor: "#4285F4", accessRole: "owner", primary: true },
          { id: "holidays", summary: "Holidays", backgroundColor: "#0b8043", accessRole: "reader" },
        ],
      });
    if (href.includes("/events?"))
      return json({
        items: href.includes("holidays")
          ? [{ id: "h1", summary: "Holiday", start: { date: "2026-12-25" }, end: { date: "2026-12-26" } }]
          : [
              {
                id: "e1",
                summary: "Dentist",
                start: { dateTime: "2026-11-13T10:00:00-05:00" },
                end: { dateTime: "2026-11-13T11:00:00-05:00" },
              },
              { id: "e2", status: "cancelled" },
            ],
      });
    if (options.method === "PATCH" || options.method === "DELETE") return json({});
    throw Error("Unexpected request " + href);
  };
  return { calls, fetch };
}

/** Plays the browser: follows the sign-in link back to Orbit's loopback address with a code. */
const browser =
  (code = "the-code") =>
  async (url) => {
    const link = new URL(url);
    const back = new URL(link.searchParams.get("redirect_uri"));
    back.searchParams.set("code", code);
    back.searchParams.set("state", link.searchParams.get("state"));
    setTimeout(() => void globalThis.fetch(back).catch(() => {}), 10);
  };

test("connecting Google signs in through the browser and loads its calendars and events", async () => {
  const google = fakeGoogle();
  let saved = null,
    changes = 0,
    opened = "";
  const accounts = new CalendarAccounts({
    config: { googleClientId: "client", googleClientSecret: "secret" },
    load: () => null,
    save: (text) => (saved = text),
    open: async (url) => {
      opened = url;
      await browser()(url);
    },
    onChange: () => changes++,
    fetch: google.fetch,
  });
  const account = await accounts.connect("google");
  assert.equal(account.email, "me@gmail.com");
  const link = new URL(opened);
  assert.equal(link.searchParams.get("code_challenge_method"), "S256");
  assert.equal(link.searchParams.get("access_type"), "offline");
  assert.match(link.searchParams.get("redirect_uri"), /^http:\/\/127\.0\.0\.1:\d+\/$/);
  assert.equal(JSON.parse(saved)[0].refreshToken, "refresh-1");
  const snapshot = accounts.snapshot();
  assert.equal(JSON.stringify(snapshot).includes("refresh-1"), false, "tokens never reach the page");
  assert.deepEqual(
    snapshot.calendars.map((c) => [c.title, c.writable, c.shown, c.color]),
    [
      ["Me", true, true, "#4285f4"],
      ["Holidays", false, true, "#0b8043"],
    ],
  );
  assert.deepEqual(
    snapshot.events.map((e) => e.title),
    ["Dentist", "Holiday"],
  );
  assert.equal(snapshot.events[0].start, Date.parse("2026-11-13T15:00:00Z"));
  assert.ok(changes > 0);

  // Editing goes straight to Google; a read-only calendar refuses.
  const dentist = snapshot.events[0];
  await accounts.update(dentist.id, { title: "Dentist checkup" });
  const patch = google.calls.find((call) => call.method === "PATCH");
  assert.match(patch.url, /\/calendars\/me%40gmail\.com\/events\/e1$/);
  assert.deepEqual(JSON.parse(patch.body), { summary: "Dentist checkup" });
  await assert.rejects(accounts.remove(snapshot.events[1].id), /read-only/);

  // Hiding a calendar stops loading its events; disconnecting forgets the account.
  await accounts.setShown(snapshot.calendars[1].id, false);
  assert.deepEqual(
    accounts.snapshot().events.map((e) => e.title),
    ["Dentist"],
  );
  await accounts.disconnect(account.id);
  assert.deepEqual(JSON.parse(saved), []);
  assert.equal(accounts.snapshot().events.length, 0);
  assert.ok(google.calls.some((call) => call.url.includes("/revoke")));
});

test("a sign-in answered with the wrong state is refused", async () => {
  const accounts = new CalendarAccounts({
    config: { microsoftClientId: "client" },
    load: () => null,
    save: () => {},
    open: async (url) => {
      const back = new URL(new URL(url).searchParams.get("redirect_uri"));
      back.searchParams.set("code", "x");
      back.searchParams.set("state", "forged");
      setTimeout(() => void globalThis.fetch(back).catch(() => {}), 10);
    },
    fetch: async () => json({}),
  });
  await assert.rejects(accounts.connect("microsoft"), /cancelled/);
});

test("a build without client ids can't start a sign-in", async () => {
  const accounts = new CalendarAccounts({ load: () => null, save: () => {}, open: async () => {} });
  assert.deepEqual(accounts.snapshot().available, { google: false, microsoft: false });
  await assert.rejects(accounts.connect("google"), /isn't set up/);
});

test("Microsoft and Google events become Orbit events; edits become each service's body", () => {
  const calendar = { id: "cal", account: "acct" };
  assert.deepEqual(
    microsoftEvent(calendar, {
      id: "m1",
      subject: "Trip",
      isAllDay: true,
      start: { dateTime: "2026-11-20T00:00:00.0000000" },
      end: { dateTime: "2026-11-23T00:00:00.0000000" },
      type: "singleInstance",
    }),
    {
      id: microsoftEvent(calendar, { id: "m1", isAllDay: true, start: { dateTime: "2026-11-20T00:00:00" } }).id,
      remoteID: "m1",
      calendarID: "cal",
      account: "acct",
      provider: "microsoft",
      title: "Trip",
      recurring: false,
      allDay: true,
      startDay: "2026-11-20",
      endDay: "2026-11-23",
    },
  );
  const timed = microsoftEvent(calendar, {
    id: "m2",
    subject: "Call",
    start: { dateTime: "2026-11-13T15:00:00.0000000" },
    end: { dateTime: "2026-11-13T15:30:00.0000000" },
    type: "occurrence",
  });
  assert.equal(timed.start, Date.parse("2026-11-13T15:00:00Z"));
  assert.equal(timed.recurring, true);
  assert.equal(microsoftEvent(calendar, { id: "m3", isCancelled: true }), null);
  assert.equal(
    googleEvent(calendar, { id: "g", recurringEventId: "r", start: { date: "2026-11-01" } }).endDay,
    "2026-11-02",
  );
  const start = Date.parse("2026-11-13T15:00:00Z");
  assert.deepEqual(microsoftBody({ title: "Call", allDay: false, start, end: start + 1800000 }), {
    subject: "Call",
    isAllDay: false,
    start: { dateTime: "2026-11-13T15:00:00", timeZone: "UTC" },
    end: { dateTime: "2026-11-13T15:30:00", timeZone: "UTC" },
  });
  assert.deepEqual(googleBody({ allDay: true, startDay: "2026-11-20", endDay: "2026-11-22" }), {
    start: { date: "2026-11-20" },
    end: { date: "2026-11-22" },
  });
});

test("a Google sign-in without calendar access is refused, and the browser page says why", async () => {
  let page = "",
    revoked = false;
  const accounts = new CalendarAccounts({
    config: { googleClientId: "client" },
    load: () => null,
    save: () => assert.fail("nothing is saved"),
    open: async (url) => {
      const back = new URL(new URL(url).searchParams.get("redirect_uri"));
      back.searchParams.set("code", "the-code");
      back.searchParams.set("state", new URL(url).searchParams.get("state"));
      setTimeout(async () => (page = await (await globalThis.fetch(back)).text()), 10);
    },
    fetch: async (url) => {
      if (String(url).includes("/revoke")) {
        revoked = true;
        return json({});
      }
      return json({
        access_token: "a",
        refresh_token: "r",
        expires_in: 3600,
        scope: "openid https://www.googleapis.com/auth/userinfo.email",
        id_token: jwt({ email: "me@gmail.com" }),
      });
    },
  });
  await assert.rejects(accounts.connect("google"), /permission to see and edit your calendars/);
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.match(page, /Orbit needs calendar access/);
  assert.doesNotMatch(page, /is connected/);
  assert.ok(revoked, "the partial sign-in is revoked");
  assert.equal(accounts.snapshot().accounts.length, 0);
});

test("with a website configured, the browser is sent to its connected page", async () => {
  let location = "";
  const accounts = new CalendarAccounts({
    config: { googleClientId: "client", connectedURL: "https://orbit.example/connected/" },
    load: () => null,
    save: () => {},
    open: async (url) => {
      const back = new URL(new URL(url).searchParams.get("redirect_uri"));
      back.searchParams.set("error", "access_denied");
      back.searchParams.set("state", new URL(url).searchParams.get("state"));
      setTimeout(async () => {
        location = (await globalThis.fetch(back, { redirect: "manual" })).headers.get("location");
      }, 10);
    },
    fetch: async () => json({}),
  });
  await assert.rejects(accounts.connect("google"), /cancelled/);
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(location, "https://orbit.example/connected/?service=google&status=cancelled");
});
