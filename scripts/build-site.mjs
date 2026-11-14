#!/usr/bin/env node
// Builds the website into a folder: copies site/, and turns docs/PRIVACY.md into privacy.html so the policy has one source.
// Usage: node scripts/build-site.mjs [out-folder]   (default: dist-site)
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/** Inline markdown: **bold**, [text](url), `code`. Everything else is escaped. */
export function inline(text) {
  return esc(text)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2">$1</a>');
}

/** A small converter for the subset used in docs/PRIVACY.md: #, ##, bullets, paragraphs. */
export function markdownToHtml(md) {
  const out = [];
  let list = false;
  let para = [];
  const flushPara = () => { if (para.length) { out.push(`<p>${inline(para.join(" "))}</p>`); para = []; } };
  const closeList = () => { if (list) { out.push("</ul>"); list = false; } };
  for (const raw of md.split("\n")) {
    const line = raw.trimEnd();
    if (/^#\s/.test(line)) { flushPara(); closeList(); out.push(`<h1>${inline(line.slice(2))}</h1>`); }
    else if (/^##\s/.test(line)) { flushPara(); closeList(); out.push(`<h2>${inline(line.slice(3))}</h2>`); }
    else if (/^-\s/.test(line)) { flushPara(); if (!list) { out.push("<ul>"); list = true; } out.push(`<li>${inline(line.slice(2))}</li>`); }
    else if (line === "") { flushPara(); closeList(); }
    else { closeList(); para.push(line); }
  }
  flushPara(); closeList();
  return out.join("\n");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const out = join(root, process.argv[2] ?? "dist-site");
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  cpSync(join(root, "site"), out, { recursive: true, filter: (src) => !src.endsWith("page.template.html") });
  const template = readFileSync(join(root, "site", "page.template.html"), "utf8");
  const privacy = readFileSync(join(root, "docs", "PRIVACY.md"), "utf8");
  const html = template
    .replace("{{title}}", "Privacy")
    .replace("{{description}}", "Quiet Feed collects nothing. What stays on your phone, what the app connects to, and the permissions it asks for.")
    .replace("{{content}}", markdownToHtml(privacy));
  writeFileSync(join(out, "privacy.html"), html);
  console.log(`built ${out}`);
}
