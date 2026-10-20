const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { generate, files } = require("../scripts/tokens.cjs");

test("generated colour files match shared/design-tokens.json (run npm run tokens)", () => {
  const output = generate();
  assert.equal(fs.readFileSync(files.css, "utf8"), output.css);
  assert.equal(fs.readFileSync(files.swift, "utf8"), output.swift);
});
