// Generates platform files from the shared JSON sources, so both apps use one copy:
// shared/design-tokens.json → windows/ui/tokens.css, ios/Shared/DesignTokens.swift
// shared/onboarding.json → windows/ui/onboarding-data.js, ios/Shared/OnboardingData.swift
// Usage: npm run generate. tests/generated.test.cjs checks the files are current.
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const kebab = (name) => name.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase());
const cap = (name) => name[0].toUpperCase() + name.slice(1);
const files = {
  css: path.join(root, "windows/ui/tokens.css"),
  swift: path.join(root, "ios/Shared/DesignTokens.swift"),
  onboardingJS: path.join(root, "windows/ui/onboarding-data.js"),
  onboardingSwift: path.join(root, "ios/Shared/OnboardingData.swift"),
};

/**
 * A spring as CSS: simulates the motion (mass, stiffness, damping) until it settles and
 * returns `linear()` easing points plus the duration, so Windows moves like the website.
 */
function springCurve({ stiffness, damping, mass = 1 }) {
  const dt = 1 / 600;
  let x = 0,
    v = 0,
    t = 0,
    still = 0;
  const samples = [0];
  while (t < 2 && still < 0.05) {
    const a = (-stiffness * (x - 1) - damping * v) / mass;
    v += a * dt;
    x += v * dt;
    t += dt;
    samples.push(x);
    still = Math.abs(x - 1) < 0.001 && Math.abs(v) < 0.01 ? still + dt : 0;
  }
  const points = 24;
  const curve = Array.from(
    { length: points + 1 },
    (_, i) => +samples[Math.round((i / points) * (samples.length - 1))].toFixed(3),
  );
  curve[points] = 1;
  return { easing: `linear(${curve.join(", ")})`, ms: Math.round(t * 1000) };
}
/** A spring in SwiftUI terms: response is the undamped period, dampingFraction the damping ratio (capped at 1). */
function springSwift({ stiffness, damping, mass = 1 }) {
  const omega = Math.sqrt(stiffness / mass);
  return {
    response: +((2 * Math.PI) / omega).toFixed(2),
    damping: +Math.min(1, damping / (2 * Math.sqrt(stiffness * mass))).toFixed(2),
  };
}

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
    ...Object.entries(tokens.type)
      .filter(([, v]) => v.size)
      .flatMap(([name, v]) => [
        `  --type-${kebab(name)}: ${v.size}px;`,
        ...(v.tracking !== undefined ? [`  --type-${kebab(name)}-tracking: ${v.tracking}em;`] : []),
      ]),
    ...Object.entries(tokens.rows).map(([name, value]) => `  --row-${kebab(name)}: ${value}px;`),
    ...Object.entries(tokens.layout).map(([name, value]) => `  --${kebab(name)}: ${value}px;`),
    ...Object.entries(tokens.tints).map(([name, value]) => `  --tint-${kebab(name)}: ${Math.round(value * 100)}%;`),
    `  --grid-weeks: ${tokens.grid.weeks};`,
    `  --grid-gap: ${tokens.grid.gap}px;`,
    `  --grid-radius: ${tokens.grid.radius}px;`,
    `  --grid-min-opacity: ${tokens.grid.minOpacity};`,
    ...Object.entries(tokens.motion.springs).flatMap(([name, spring]) => {
      const curve = springCurve(spring);
      return [`  --spring-${name}: ${curve.easing};`, `  --spring-${name}-duration: ${curve.ms}ms;`];
    }),
    `  --stagger: ${tokens.motion.staggerMilliseconds}ms;`,
    `  --row-slide: ${tokens.motion.rowSlide}px;`,
    `  --tick-draw: ${tokens.motion.tickDrawMilliseconds}ms;`,
    `  --tick-pop: ${tokens.motion.tickPop};`,
    `  --press-scale: ${tokens.motion.pressScale};`,
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
    ...Object.entries(tokens.type)
      .filter(([, v]) => v.size)
      .flatMap(([name, v]) => [
        `    static let type${cap(name)}: Double = ${v.size}`,
        ...(v.tracking !== undefined ? [`    static let type${cap(name)}Tracking: Double = ${v.tracking}`] : []),
      ]),
    ...Object.entries(tokens.rows).map(([name, value]) => `    static let row${cap(name)}: Double = ${value}`),
    ...Object.entries(tokens.layout).map(([name, value]) => `    static let ${name}: Double = ${value}`),
    ...Object.entries(tokens.tints).map(([name, value]) => `    static let tint${cap(name)}: Double = ${value}`),
    `    static let gridWeeks = ${tokens.grid.weeks}`,
    `    static let gridGap: Double = ${tokens.grid.gap}`,
    `    static let gridRadius: Double = ${tokens.grid.radius}`,
    `    static let gridMinOpacity: Double = ${tokens.grid.minOpacity}`,
    ...Object.entries(tokens.motion.springs).flatMap(([name, spring]) => {
      const swift = springSwift(spring);
      return [
        `    static let spring${cap(name)}: (response: Double, damping: Double) = (${swift.response}, ${swift.damping})`,
      ];
    }),
    `    static let staggerSeconds: Double = ${tokens.motion.staggerMilliseconds / 1000}`,
    `    static let rowSlide: Double = ${tokens.motion.rowSlide}`,
    `    static let tickDrawSeconds: Double = ${tokens.motion.tickDrawMilliseconds / 1000}`,
    `    static let tickPop: Double = ${tokens.motion.tickPop}`,
    `    static let pressScale: Double = ${tokens.motion.pressScale}`,
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
