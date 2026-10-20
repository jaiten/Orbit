// Generates platform files from the shared JSON sources, so both apps use one copy:
// shared/design-tokens.json → windows/ui/tokens.css, ios/Shared/DesignTokens.swift
// shared/onboarding.json → windows/ui/onboarding-data.js, ios/Shared/OnboardingData.swift
// Usage: npm run generate. tests/generated.test.cjs checks the files are current.
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const files = {
  css: path.join(root, "windows/ui/tokens.css"),
  swift: path.join(root, "ios/Shared/DesignTokens.swift"),
  onboardingJS: path.join(root, "windows/ui/onboarding-data.js"),
  onboardingSwift: path.join(root, "ios/Shared/OnboardingData.swift"),
};

function generate(tokens = JSON.parse(fs.readFileSync(path.join(root, "shared/design-tokens.json"), "utf8"))) {
  const header = "Generated from shared/design-tokens.json by windows/scripts/generate.cjs. Do not edit.";
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
  return { css, swift, ...generateOnboarding() };
}

function generateOnboarding(data = JSON.parse(fs.readFileSync(path.join(root, "shared/onboarding.json"), "utf8"))) {
  const header = "Generated from shared/onboarding.json by windows/scripts/generate.cjs. Do not edit.";
  const { description, ...content } = data;
  void description;
  const onboardingJS = `// ${header}\nconst OrbitOnboardingData = ${JSON.stringify(content, null, 2)};\nif (typeof module === "object") module.exports = OrbitOnboardingData;\n`;
  const str = (value) => (value === undefined || value === null ? "nil" : JSON.stringify(value));
  const num = (value) => (value === undefined || value === null ? "nil" : String(value));
  const { lists, tasks, habits } = content.examples;
  const onboardingSwift = [
    `// ${header}`,
    "import Foundation",
    "",
    "enum OnboardingData {",
    "    struct ExampleList { let id: String; let name: String; let color: String }",
    "    struct ExampleTask { let id: String; let title: String; let time: Int?; let minutes: Int?; let list: String?; let someday: Bool }",
    "    struct ExampleHabit { let id: String; let title: String; let frequencyRule: String; let target: Int; let color: String }",
    "    struct HabitSuggestion { let title: String; let frequencyRule: String; let target: Int; let reminderMinutes: Int? }",
    "    static let exampleLists = [",
    ...lists.map((l) => `        ExampleList(id: ${str(l.id)}, name: ${str(l.name)}, color: ${str(l.color)}),`),
    "    ]",
    "    static let exampleTasks = [",
    ...tasks.map(
      (t) =>
        `        ExampleTask(id: ${str(t.id)}, title: ${str(t.title)}, time: ${num(t.time)}, minutes: ${num(t.minutes)}, list: ${str(t.list)}, someday: ${t.someday === true}),`,
    ),
    "    ]",
    "    static let exampleHabits = [",
    ...habits.map(
      (h) =>
        `        ExampleHabit(id: ${str(h.id)}, title: ${str(h.title)}, frequencyRule: ${str(h.frequencyRule)}, target: ${h.target}, color: ${str(h.color)}),`,
    ),
    "    ]",
    "    static let habitSuggestions = [",
    ...content.habitSuggestions.map(
      (h) =>
        `        HabitSuggestion(title: ${str(h.title)}, frequencyRule: ${str(h.frequencyRule)}, target: ${h.target}, reminderMinutes: ${num(h.reminderMinutes)}),`,
    ),
    "    ]",
    "}",
    "",
  ].join("\n");
  return { onboardingJS, onboardingSwift };
}

if (require.main === module) {
  const output = generate();
  for (const [name, file] of Object.entries(files)) {
    fs.writeFileSync(file, output[name]);
    console.log("Wrote", path.relative(root, file));
  }
}

module.exports = { generate, files };
