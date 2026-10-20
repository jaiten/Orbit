// Generates windows/ui/tokens.css and ios/Shared/DesignTokens.swift from shared/design-tokens.json.
// Usage: node scripts/tokens.cjs (writes both files). tests/tokens.test.cjs checks they are current.
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const files = {
  css: path.join(root, "windows/ui/tokens.css"),
  swift: path.join(root, "ios/Shared/DesignTokens.swift"),
};

function generate(tokens = JSON.parse(fs.readFileSync(path.join(root, "shared/design-tokens.json"), "utf8"))) {
  const header = "Generated from shared/design-tokens.json by windows/scripts/tokens.cjs. Do not edit.";
  const pair = (value) => `light-dark(${value.light}, ${value.dark})`;
  const css = [
    `/* ${header} */`,
    ":root {",
    "  color-scheme: light dark;",
    ...Object.entries(tokens.surfaces).map(([name, value]) => `  --${name}: ${pair(value)};`),
    ...Object.entries(tokens.palette).map(([name, value]) => `  --${name}: ${value};`),
    ...Object.entries(tokens.spacing).map(([name, value]) => `  --space-${name}: ${value}px;`),
    ...Object.entries(tokens.radii).map(([name, value]) => `  --radius-${name}: ${value}px;`),
    `  --motion: ${tokens.motion.standardMilliseconds}ms;`,
    "}",
    ...Object.entries(tokens.accents).flatMap(([name, accent]) => [
      `${name === "coral" ? ":root,\n" : ""}:root[data-accent="${name}"] {`,
      `  --accent: ${accent.fill};`,
      `  --accent-text: ${pair(accent.text)};`,
      // Filled controls: the darker text colour in light mode keeps white labels legible.
      `  --accent-button: light-dark(${accent.text.light}, ${accent.fill});`,
      `  --on-accent: light-dark(#ffffff, #141416);`,
      "}",
    ]),
    "",
  ].join("\n");

  const hex = (value) => "0x" + value.slice(1).toUpperCase();
  const swiftPair = (value) => `(light: ${hex(value.light)}, dark: ${hex(value.dark)})`;
  const dictionary = (entries) => `[${entries.map(([k, v]) => `"${k}": ${v}`).join(", ")}]`;
  const swift = [
    `// ${header}`,
    "import Foundation",
    "",
    "enum DesignTokens {",
    "    typealias Pair = (light: Int, dark: Int)",
    `    static let accentFill: [String: Int] = ${dictionary(Object.entries(tokens.accents).map(([k, v]) => [k, hex(v.fill)]))}`,
    `    static let accentText: [String: Pair] = ${dictionary(Object.entries(tokens.accents).map(([k, v]) => [k, swiftPair(v.text)]))}`,
    `    static let palette: [String: Int] = ${dictionary(Object.entries(tokens.palette).map(([k, v]) => [k, hex(v)]))}`,
    ...Object.entries(tokens.surfaces).map(([name, value]) => `    static let ${name}: Pair = ${swiftPair(value)}`),
    ...Object.entries(tokens.spacing).map(
      ([name, value]) => `    static let space${name[0].toUpperCase() + name.slice(1)}: Double = ${value}`,
    ),
    ...Object.entries(tokens.radii).map(
      ([name, value]) => `    static let radius${name[0].toUpperCase() + name.slice(1)}: Double = ${value}`,
    ),
    `    static let motionSeconds: Double = ${tokens.motion.standardMilliseconds / 1000}`,
    "}",
    "",
  ].join("\n");
  return { css, swift };
}

if (require.main === module) {
  const output = generate();
  fs.writeFileSync(files.css, output.css);
  fs.writeFileSync(files.swift, output.swift);
  console.log("Wrote", path.relative(root, files.css), "and", path.relative(root, files.swift));
}

module.exports = { generate, files };
