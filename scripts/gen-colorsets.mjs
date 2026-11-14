#!/usr/bin/env node
// Writes App/Resources/Assets.xcassets/<token>.colorset from design/tokens.json.
// Usage: node scripts/gen-colorsets.mjs
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const tokens = JSON.parse(readFileSync(join(root, "design", "tokens.json"), "utf8")).colors;

const components = (hex) => {
  const h = hex.replace("#", "").toUpperCase();
  return {
    "color-space": "srgb",
    components: { red: `0x${h.slice(0, 2)}`, green: `0x${h.slice(2, 4)}`, blue: `0x${h.slice(4, 6)}`, alpha: "1.000" },
  };
};

for (const [name, v] of Object.entries(tokens)) {
  const dir = join(root, "App", "Resources", "Assets.xcassets", `${name}.colorset`);
  mkdirSync(dir, { recursive: true });
  const json = {
    colors: [
      { idiom: "universal", color: components(v.light) },
      {
        idiom: "universal",
        appearances: [{ appearance: "luminosity", value: "dark" }],
        color: components(v.dark),
      },
    ],
    info: { author: "xcode", version: 1 },
  };
  writeFileSync(join(dir, "Contents.json"), JSON.stringify(json, null, 2) + "\n");
}
console.log(`wrote ${Object.keys(tokens).length} colour sets`);
