const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// The page's scripts share one global scope (plain <script> tags), so two files defining the same
// top-level function or constant silently replace one another. Catch that here.
test("no two UI scripts define the same top-level name", () => {
  const folder = path.join(__dirname, "../ui");
  const files = [
    ...fs.readdirSync(folder).map((name) => path.join(folder, name)),
    ...fs.readdirSync(path.join(folder, "pages")).map((name) => path.join(folder, "pages", name)),
  ].filter((file) => file.endsWith(".js"));
  const seen = new Map();
  const clashes = [];
  for (const file of files) {
    const source = fs.readFileSync(file, "utf8");
    for (const match of source.matchAll(
      /^(?:async\s+)?(?:function\s+([A-Za-z0-9_$]+)|(?:const|let|class)\s+([A-Za-z0-9_$]+))/gm,
    )) {
      const name = match[1] || match[2];
      const where = path.relative(folder, file);
      if (seen.has(name) && seen.get(name) !== where) clashes.push(`${name}: ${seen.get(name)} and ${where}`);
      else seen.set(name, where);
    }
  }
  assert.deepEqual(clashes, []);
});
