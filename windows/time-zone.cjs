// Windows sometimes knows a time zone the browser engine doesn't: in 2026 British Columbia moved to
// UTC−7 all year, and Windows calls it "(UTC-07:00) Pacific Time (British Columbia)", but Chromium maps
// that machine to Los Angeles rules, so every time showed an hour early in winter. This reads Windows'
// own zone and offset and, when the engine disagrees, names the IANA zone to use instead.

/** Minutes east of UTC for an IANA zone at a moment, e.g. -420 for UTC−7. */
function offsetIn(zone, at = Date.now()) {
  const name = new Intl.DateTimeFormat("en-US", { timeZone: zone, timeZoneName: "longOffset" })
    .formatToParts(new Date(at))
    .find((part) => part.type === "timeZoneName")?.value;
  const match = /GMT(?:([+-])(\d{2}):?(\d{2})?)?/.exec(name || "");
  if (!match || !match[1]) return 0;
  return (match[1] === "-" ? -1 : 1) * (Number(match[2]) * 60 + Number(match[3] || 0));
}

// Windows zones whose people live in one IANA zone that the engine's own mapping gets wrong.
const KNOWN = [
  [/british columbia/i, "America/Vancouver"],
  [/yukon/i, "America/Whitehorse"],
];

/**
 * The IANA zone to use, or null when the engine's own zone already matches Windows.
 * @param {{id: string, name: string, offset: number, daylight: boolean}} windows  Windows' zone now
 * @param {string} engineZone  the zone the engine picked (Intl's resolved time zone)
 */
function correctedZone(windows, engineZone, { now = Date.now(), zones = Intl.supportedValuesOf("timeZone") } = {}) {
  if (!windows || !Number.isFinite(windows.offset)) return null;
  if (offsetIn(engineZone, now) === windows.offset) return null;
  const label = `${windows.id} ${windows.name}`;
  for (const [pattern, zone] of KNOWN) if (pattern.test(label) && offsetIn(zone, now) === windows.offset) return zone;
  // Otherwise a zone with the same offset now and the same habit of changing clocks, from the same
  // part of the world as the engine's guess when there is one.
  const year = new Date(now).getUTCFullYear();
  const changes = (zone) => offsetIn(zone, Date.UTC(year, 0, 15)) !== offsetIn(zone, Date.UTC(year, 6, 15));
  const region = engineZone.split("/")[0];
  const candidates = zones.filter(
    (zone) => offsetIn(zone, now) === windows.offset && changes(zone) === !!windows.daylight,
  );
  const pick = candidates.find((zone) => zone.startsWith(region + "/")) || candidates[0];
  if (pick) return pick;
  // Etc zones count the other way: Etc/GMT+7 is UTC−7.
  return windows.offset % 60 ? null : `Etc/GMT${windows.offset <= 0 ? "+" : "-"}${Math.abs(windows.offset / 60)}`;
}

/** Windows' zone, from PowerShell: id, display name, current offset and whether it changes clocks. */
function parseWindowsZone(text) {
  const [id, name, offset, daylight] = String(text).trim().split("|");
  return id ? { id, name: name || "", offset: Number(offset), daylight: /true/i.test(daylight || "") } : null;
}
const WINDOWS_ZONE_SCRIPT =
  "$z=[TimeZoneInfo]::Local; [Console]::Out.Write(($z.Id,$z.DisplayName,$z.GetUtcOffset([DateTime]::UtcNow).TotalMinutes,$z.SupportsDaylightSavingTime) -join '|')";

module.exports = { offsetIn, correctedZone, parseWindowsZone, WINDOWS_ZONE_SCRIPT };
