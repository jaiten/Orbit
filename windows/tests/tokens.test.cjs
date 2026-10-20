const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { generate, files } = require("../scripts/tokens.cjs");

test("generated colour files match shared/design-tokens.json (run npm run tokens)", () => {
  const output = generate();
  // Git may check files out with CRLF on Windows; compare the content, not the line endings.
  const read = (file) => fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  assert.equal(read(files.css), output.css);
  assert.equal(read(files.swift), output.swift);
});
