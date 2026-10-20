const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { generate, files } = require("../scripts/generate.cjs");

test("generated files match shared/design-tokens.json and shared/onboarding.json (run npm run generate)", () => {
  const output = generate();
  // Git may check files out with CRLF on Windows; compare the content, not the line endings.
  const read = (file) => fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  for (const [name, file] of Object.entries(files)) assert.equal(read(file), output[name], file);
});
