// Google Calendar and Microsoft (Outlook, Microsoft 365) accounts linked on this PC. Sign-in runs in the
// user's browser (OAuth with PKCE, answered on a loopback address), the refresh token is kept encrypted
// on this PC, and events are read and changed through each service's own API. Nothing here goes through
// Orbit sync: Apple calendars reach Windows from the iPhone instead (see ui/calendar-events.js).
const http = require("node:http");
const { createHash, randomBytes } = require("node:crypto");

const PROVIDERS = {
  google: {
    name: "Google",
    auth: "https://accounts.google.com/o/oauth2/v2/auth",
    token: "https://oauth2.googleapis.com/token",
    scope: "openid email https://www.googleapis.com/auth/calendar",
    host: "127.0.0.1",
    extra: { access_type: "offline", prompt: "consent" },
  },
  microsoft: {
    name: "Microsoft",
    auth: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
    token: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
    scope: "openid email offline_access User.Read Calendars.ReadWrite",
    host: "localhost",
    extra: { prompt: "select_account" },
  },
};

const base64url = (buffer) => buffer.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const pad = (n) => String(n).padStart(2, "0");
const dayKey = (date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const addDays = (key, days) => {
  const date = new Date(`${key}T12:00:00`);
  date.setDate(date.getDate() + days);
  return dayKey(date);
};
/** Ids Orbit uses for linked calendars and events: short, stable and safe in HTML attributes. */
const shortID = (...parts) => createHash("sha256").update(parts.join("|")).digest("hex").slice(0, 32);
const hexColor = (value) => (/^#[0-9a-f]{6}$/i.test(value || "") ? value.toLowerCase() : "#8e8e93");
const claims = (jwt) => {
  try {
    return JSON.parse(Buffer.from(String(jwt).split(".")[1], "base64url").toString("utf8"));
  } catch {
    return {};
  }
};

/** A Google calendarList entry, in Orbit's shape. */
function googleCalendar(account, item) {
  return {
    id: shortID(account.id, item.id),
    remoteID: item.id,
    account: account.id,
    provider: "google",
    title: item.summaryOverride || item.summary || "Calendar",
    color: hexColor(item.backgroundColor),
    writable: ["owner", "writer"].includes(item.accessRole),
    primary: !!item.primary,
  };
}
/** A Google event instance (singleEvents=true), in the shape the calendar views use. */
function googleEvent(calendar, item) {
  if (item.status === "cancelled") return null;
  const base = {
    id: shortID(calendar.id, item.id),
    remoteID: item.id,
    calendarID: calendar.id,
    account: calendar.account,
    provider: "google",
    title: item.summary || "(No title)",
    recurring: !!item.recurringEventId,
  };
  if (item.start?.date)
    return { ...base, allDay: true, startDay: item.start.date, endDay: item.end?.date || addDays(item.start.date, 1) };
  const start = Date.parse(item.start?.dateTime),
    end = Date.parse(item.end?.dateTime);
  return Number.isFinite(start)
    ? { ...base, allDay: false, start, end: Number.isFinite(end) ? end : start + 30 * 60000 }
    : null;
}
function microsoftCalendar(account, item) {
  return {
    id: shortID(account.id, item.id),
    remoteID: item.id,
    account: account.id,
    provider: "microsoft",
    title: item.name || "Calendar",
    color: hexColor(item.hexColor),
    writable: item.canEdit !== false,
    primary: !!item.isDefaultCalendar,
  };
}
/** A Microsoft Graph calendarView occurrence (times asked for in UTC). */
function microsoftEvent(calendar, item) {
  if (item.isCancelled) return null;
  const base = {
    id: shortID(calendar.id, item.id),
    remoteID: item.id,
    calendarID: calendar.id,
    account: calendar.account,
    provider: "microsoft",
    title: item.subject || "(No title)",
    recurring: item.type === "occurrence" || item.type === "exception",
  };
  const utc = (value) => Date.parse(String(value || "").replace(/(\.\d{3})\d*$/, "$1") + "Z");
  if (item.isAllDay) {
    // All-day events come back as UTC midnights that stand for calendar days.
    const startDay = String(item.start?.dateTime || "").slice(0, 10),
      endDay = String(item.end?.dateTime || "").slice(0, 10);
    return /^\d{4}-\d{2}-\d{2}$/.test(startDay)
      ? { ...base, allDay: true, startDay, endDay: endDay > startDay ? endDay : addDays(startDay, 1) }
      : null;
  }
  const start = utc(item.start?.dateTime),
    end = utc(item.end?.dateTime);
  return Number.isFinite(start)
    ? { ...base, allDay: false, start, end: Number.isFinite(end) ? end : start + 30 * 60000 }
    : null;
}

/** The body for changing an event. All-day end days are exclusive, as both services expect. */
function googleBody(changes) {
  const body = {};
  if (changes.title !== undefined) body.summary = changes.title;
  if (changes.allDay === true)
    Object.assign(body, {
      start: { date: changes.startDay },
      end: { date: changes.endDay || addDays(changes.startDay, 1) },
    });
  if (changes.allDay === false)
    Object.assign(body, {
      start: { dateTime: new Date(changes.start).toISOString() },
      end: { dateTime: new Date(changes.end).toISOString() },
    });
  return body;
}
function microsoftBody(changes) {
  const body = {};
  if (changes.title !== undefined) body.subject = changes.title;
  const utc = (stamp) => ({ dateTime: new Date(stamp).toISOString().slice(0, 19), timeZone: "UTC" });
  if (changes.allDay === true) {
    const end = changes.endDay || addDays(changes.startDay, 1);
    Object.assign(body, {
      isAllDay: true,
      start: { dateTime: `${changes.startDay}T00:00:00`, timeZone: changes.timeZone || "UTC" },
      end: { dateTime: `${end}T00:00:00`, timeZone: changes.timeZone || "UTC" },
    });
  }
  if (changes.allDay === false)
    Object.assign(body, { isAllDay: false, start: utc(changes.start), end: utc(changes.end) });
  return body;
}

class CalendarAccounts {
  /**
   * @param {object} options
   * @param {object} options.config  client ids: googleClientId, googleClientSecret, microsoftClientId
   * @param {() => string|null} options.load  reads the encrypted account list
   * @param {(text: string) => void} options.save  writes it
   * @param {(url: string) => Promise<void>} options.open  opens the sign-in page in the browser
   * @param {() => void} options.onChange  called when calendars or events change
   */
  constructor({
    config = {},
    load,
    save,
    open,
    onChange = () => {},
    fetch = globalThis.fetch,
    urls = {},
    now = Date.now,
  }) {
    Object.assign(this, { config, load, save, open, onChange, fetch, now });
    this.providers = Object.fromEntries(
      Object.entries(PROVIDERS).map(([key, value]) => [key, { ...value, ...urls[key] }]),
    );
    this.api = {
      google: "https://www.googleapis.com/calendar/v3",
      microsoft: "https://graph.microsoft.com/v1.0",
      ...urls.api,
    };
    this.tokens = new Map();
    this.calendars = [];
    this.events = [];
    this.errors = {};
    this.refreshing = null;
    try {
      this.accounts = JSON.parse(load() || "[]");
    } catch {
      this.accounts = [];
    }
  }
  available(provider) {
    return provider === "google"
      ? !!this.config.googleClientId
      : provider === "microsoft"
        ? !!this.config.microsoftClientId
        : false;
  }
  persist() {
    this.save(JSON.stringify(this.accounts));
  }
  /** What the renderer shows: accounts (never tokens), their calendars and events. */
  snapshot() {
    return {
      available: { google: this.available("google"), microsoft: this.available("microsoft") },
      accounts: this.accounts.map(({ id, provider, email, hidden = [] }) => ({
        id,
        provider,
        email,
        hidden,
        error: this.errors[id] || null,
      })),
      calendars: this.calendars.map((calendar) => ({
        ...calendar,
        shown: !this.accounts.find((account) => account.id === calendar.account)?.hidden?.includes(calendar.id),
        email: this.accounts.find((account) => account.id === calendar.account)?.email || "",
      })),
      events: this.events,
    };
  }

  /** Signs in through the browser and adds the account. */
  async connect(provider) {
    const settings = this.providers[provider];
    if (!settings || !this.available(provider))
      throw Error("This build of Orbit isn't set up to connect that calendar.");
    const verifier = base64url(randomBytes(48)),
      state = base64url(randomBytes(24));
    const { code, redirect } = await this.listen(settings.host, state, async (redirectURI) => {
      const url = new URL(settings.auth);
      const params = {
        client_id: this.clientID(provider),
        redirect_uri: redirectURI,
        response_type: "code",
        scope: settings.scope,
        state,
        code_challenge: base64url(createHash("sha256").update(verifier).digest()),
        code_challenge_method: "S256",
        ...settings.extra,
      };
      for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
      await this.open(url.toString());
    });
    const token = await this.tokenRequest(provider, {
      grant_type: "authorization_code",
      code,
      redirect_uri: redirect,
      code_verifier: verifier,
    });
    if (!token.refresh_token) throw Error("The sign-in didn't allow Orbit to stay connected. Please try again.");
    const email =
      claims(token.id_token).email ||
      claims(token.id_token).preferred_username ||
      (await this.profileEmail(provider, token.access_token));
    const existing = this.accounts.find((account) => account.provider === provider && account.email === email);
    const account = existing || {
      id: shortID(provider, email || randomBytes(8).toString("hex")),
      provider,
      email: email || settings.name,
      hidden: [],
    };
    account.refreshToken = token.refresh_token;
    if (!existing) this.accounts.push(account);
    this.tokens.set(account.id, {
      value: token.access_token,
      expires: this.now() + (Number(token.expires_in) || 3600) * 1000,
    });
    delete this.errors[account.id];
    this.persist();
    await this.refresh();
    return { id: account.id, email: account.email };
  }
  clientID(provider) {
    return provider === "google" ? this.config.googleClientId : this.config.microsoftClientId;
  }
  /** Waits for the browser to return to a one-time loopback address with the sign-in code. */
  listen(host, state, start, timeout = 5 * 60000) {
    return new Promise((resolve, reject) => {
      let redirect = "";
      const server = http.createServer((request, response) => {
        const url = new URL(request.url, redirect);
        if (url.pathname !== "/") {
          response.writeHead(404).end();
          return;
        }
        const ok = url.searchParams.get("state") === state && url.searchParams.get("code");
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        response.end(
          `<!doctype html><meta charset="utf-8"><title>Orbit</title><body style="font:16px system-ui;margin:48px">${
            ok
              ? "Your calendar is connected. You can close this tab and return to Orbit."
              : "Orbit couldn't connect your calendar. Close this tab and try again."
          }</body>`,
        );
        finish(
          ok
            ? null
            : Error(
                url.searchParams.get("error_description") || url.searchParams.get("error") || "Sign-in was cancelled.",
              ),
          url.searchParams.get("code"),
        );
      });
      const timer = setTimeout(() => finish(Error("Sign-in timed out. Please try again.")), timeout);
      let done = false;
      const finish = (error, code) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        server.close();
        if (error) reject(error);
        else resolve({ code, redirect });
      };
      server.on("error", (error) => finish(error));
      server.listen(0, "127.0.0.1", () => {
        redirect = `http://${host}:${server.address().port}/`;
        start(redirect).catch((error) => finish(error));
      });
    });
  }
  async tokenRequest(provider, fields) {
    const body = new URLSearchParams({ client_id: this.clientID(provider), ...fields });
    if (provider === "google" && this.config.googleClientSecret)
      body.set("client_secret", this.config.googleClientSecret);
    const response = await this.fetch(this.providers[provider].token, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
    const value = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = Error(value.error_description || value.error || "Couldn't reach the calendar service.");
      error.revoked = value.error === "invalid_grant";
      throw error;
    }
    return value;
  }
  async profileEmail(provider, accessToken) {
    if (provider !== "microsoft") return "";
    const response = await this.fetch(this.api.microsoft + "/me?$select=mail,userPrincipalName", {
      headers: { Authorization: "Bearer " + accessToken },
    });
    const value = await response.json().catch(() => ({}));
    return value.mail || value.userPrincipalName || "";
  }
  async accessToken(account) {
    const cached = this.tokens.get(account.id);
    if (cached && cached.expires > this.now() + 60000) return cached.value;
    const token = await this.tokenRequest(account.provider, {
      grant_type: "refresh_token",
      refresh_token: account.refreshToken,
    });
    if (token.refresh_token && token.refresh_token !== account.refreshToken) {
      account.refreshToken = token.refresh_token;
      this.persist();
    }
    this.tokens.set(account.id, {
      value: token.access_token,
      expires: this.now() + (Number(token.expires_in) || 3600) * 1000,
    });
    return token.access_token;
  }
  async call(account, path, { method = "GET", body, headers = {} } = {}) {
    const url = path.startsWith("http") ? path : this.api[account.provider] + path;
    const response = await this.fetch(url, {
      method,
      headers: {
        Authorization: "Bearer " + (await this.accessToken(account)),
        ...(body ? { "Content-Type": "application/json" } : {}),
        ...headers,
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.status === 204) return {};
    const value = await response.json().catch(() => ({}));
    if (!response.ok) throw Error(value.error?.message || `The calendar service answered ${response.status}.`);
    return value;
  }

  /** Reloads calendars and events from two weeks ago to four months ahead. */
  refresh() {
    this.loadedAt = this.now();
    // Each refresh runs after the one before, so a change (a new account, a hidden calendar) is never
    // answered by a load that started earlier.
    this.refreshing = (this.refreshing || Promise.resolve()).catch(() => {}).then(() => this.loadAll());
    return this.refreshing;
  }
  refreshIfStale(age) {
    return this.accounts.length && this.now() - (this.loadedAt || 0) > age ? this.refresh() : this.refreshing;
  }
  async loadAll() {
    const from = new Date(this.now() - 14 * 86400000),
      to = new Date(this.now() + 120 * 86400000);
    const calendars = [],
      events = [];
    for (const account of this.accounts) {
      try {
        const own = await this.loadCalendars(account);
        calendars.push(...own);
        for (const calendar of own.filter((item) => !account.hidden?.includes(item.id)))
          events.push(...(await this.loadEvents(account, calendar, from, to)));
        delete this.errors[account.id];
      } catch (error) {
        this.errors[account.id] = error.revoked ? "Sign in again to keep this calendar connected." : error.message;
        // Keep what was shown before rather than emptying the calendar on a network hiccup.
        calendars.push(...this.calendars.filter((item) => item.account === account.id));
        events.push(...this.events.filter((item) => item.account === account.id));
      }
    }
    this.calendars = calendars;
    this.events = events;
    this.onChange();
  }
  async loadCalendars(account) {
    if (account.provider === "google") {
      const value = await this.call(account, "/users/me/calendarList?minAccessRole=reader&maxResults=250");
      return (value.items || []).filter((item) => !item.deleted).map((item) => googleCalendar(account, item));
    }
    const value = await this.call(account, "/me/calendars?$top=100");
    return (value.value || []).map((item) => microsoftCalendar(account, item));
  }
  async loadEvents(account, calendar, from, to) {
    const result = [];
    if (account.provider === "google") {
      let page = "";
      do {
        const query = new URLSearchParams({
          singleEvents: "true",
          orderBy: "startTime",
          timeMin: from.toISOString(),
          timeMax: to.toISOString(),
          maxResults: "2500",
          ...(page ? { pageToken: page } : {}),
        });
        const value = await this.call(account, `/calendars/${encodeURIComponent(calendar.remoteID)}/events?${query}`);
        result.push(...(value.items || []).map((item) => googleEvent(calendar, item)).filter(Boolean));
        page = value.nextPageToken || "";
      } while (page);
      return result;
    }
    let next = `/me/calendars/${encodeURIComponent(calendar.remoteID)}/calendarView?${new URLSearchParams({
      startDateTime: from.toISOString(),
      endDateTime: to.toISOString(),
      $top: "500",
      $select: "id,subject,start,end,isAllDay,isCancelled,type",
    })}`;
    while (next) {
      const value = await this.call(account, next, { headers: { Prefer: 'outlook.timezone="UTC"' } });
      result.push(...(value.value || []).map((item) => microsoftEvent(calendar, item)).filter(Boolean));
      next = value["@odata.nextLink"] || "";
    }
    return result;
  }

  find(eventID) {
    const event = this.events.find((item) => item.id === eventID);
    const calendar = event && this.calendars.find((item) => item.id === event.calendarID);
    const account = calendar && this.accounts.find((item) => item.id === calendar.account);
    if (!account) throw Error("That event is no longer in your calendar.");
    if (!calendar.writable) throw Error("This calendar is read-only.");
    return { event, calendar, account };
  }
  /** Changes one event (one occurrence of a repeating event) in its calendar. */
  async update(eventID, changes) {
    const { event, calendar, account } = this.find(eventID);
    if (account.provider === "google")
      await this.call(
        account,
        `/calendars/${encodeURIComponent(calendar.remoteID)}/events/${encodeURIComponent(event.remoteID)}`,
        {
          method: "PATCH",
          body: googleBody(changes),
        },
      );
    else
      await this.call(account, `/me/events/${encodeURIComponent(event.remoteID)}`, {
        method: "PATCH",
        body: microsoftBody(changes),
      });
    await this.refresh();
  }
  async remove(eventID) {
    const { event, calendar, account } = this.find(eventID);
    if (account.provider === "google")
      await this.call(
        account,
        `/calendars/${encodeURIComponent(calendar.remoteID)}/events/${encodeURIComponent(event.remoteID)}`,
        { method: "DELETE" },
      );
    else await this.call(account, `/me/events/${encodeURIComponent(event.remoteID)}`, { method: "DELETE" });
    await this.refresh();
  }
  /** Shows or hides one calendar of a linked account. */
  async setShown(calendarID, shown) {
    const calendar = this.calendars.find((item) => item.id === calendarID);
    const account = calendar && this.accounts.find((item) => item.id === calendar.account);
    if (!account) return;
    account.hidden = (account.hidden || []).filter((id) => id !== calendarID).concat(shown ? [] : [calendarID]);
    this.persist();
    await this.refresh();
  }
  /** Forgets an account on this PC; for Google the sign-in is also revoked. */
  async disconnect(accountID) {
    const account = this.accounts.find((item) => item.id === accountID);
    if (!account) return;
    this.accounts = this.accounts.filter((item) => item !== account);
    this.tokens.delete(accountID);
    delete this.errors[accountID];
    this.calendars = this.calendars.filter((item) => item.account !== accountID);
    this.events = this.events.filter((item) => item.account !== accountID);
    this.persist();
    this.onChange();
    if (account.provider === "google")
      await this.fetch("https://oauth2.googleapis.com/revoke?token=" + encodeURIComponent(account.refreshToken), {
        method: "POST",
      }).catch(() => {});
  }
}

module.exports = {
  CalendarAccounts,
  googleEvent,
  microsoftEvent,
  googleCalendar,
  microsoftCalendar,
  googleBody,
  microsoftBody,
};
