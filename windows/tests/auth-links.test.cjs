const test = require("node:test"),
  assert = require("node:assert/strict");
const { confirmationNotice } = require("../auth-links.cjs");
test("only handles the exact account callback", () => {
  for (const link of [
    "https://auth/",
    "orbit://app/",
    "orbit://evil/auth",
    "orbit://auth.evil/",
    "orbit://auth/extra",
    "not a url",
    "orbit://user:pass@auth/",
  ])
    assert.equal(confirmationNotice(link), null);
  assert.match(confirmationNotice("orbit://auth#access_token=never-reflect-this&refresh_token=private"), /Sign in/);
  assert.ok(!confirmationNotice("orbit://auth#access_token=never-reflect-this").includes("never-reflect-this"));
});
test("expired links show recovery without exposing parameters", () => {
  assert.match(confirmationNotice("orbit://auth#error=access_denied&error_code=otp_expired"), /fresh email/);
  assert.match(confirmationNotice("orbit://auth?error=invalid"), /invalid or expired/);
});
