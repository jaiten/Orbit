// After a release is published, tell running copies of Orbit for Windows to check for it now. This
// is a Supabase Realtime broadcast on the public "orbit-releases" channel, sent with the app's own
// publishable key; receiving it only starts an update check (see updates.cjs), so it carries no data
// that matters. A failed announcement leaves the hourly check to find the release.
const config = require("../config.json");

async function announceRelease({ version, fetch = globalThis.fetch, url = config.url, key = config.publishableKey }) {
  if (!/^\d+\.\d+\.\d+$/.test(version || "")) throw Error("Invalid release version");
  const response = await fetch(new URL("/realtime/v1/api/broadcast", url), {
    method: "POST",
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify({ messages: [{ topic: "orbit-releases", event: "release", payload: { version } }] }),
  });
  if (!response.ok) throw Error(`Announcement failed (HTTP ${response.status})`);
}

if (require.main === module)
  announceRelease({ version: process.env.ORBIT_RELEASE_VERSION }).then(
    () => console.log("Announced Orbit", process.env.ORBIT_RELEASE_VERSION),
    (error) => {
      console.error(error.message);
      process.exitCode = 1;
    },
  );

module.exports = { announceRelease };
