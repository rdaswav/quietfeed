#!/usr/bin/env node
// Mirrors Packages/QuietFeedCore/.../RulePackValidator.swift. Keep the two in step.
import { readFileSync } from "node:fs";

const MAX_BYTES = 256 * 1024;
const MAX_SITES = 10;
const MAX_LIST = 200;
const MAX_SELECTOR = 300;
const KNOWN_IDS = ["instagram", "youtube", "facebook"];
const FORBIDDEN = /[{}<>;]/;

export function validate(buf) {
  const errors = [];
  if (buf.length >= MAX_BYTES) {
    return [`pack is ${buf.length} bytes, must be under ${MAX_BYTES}`];
  }
  let pack;
  try {
    pack = JSON.parse(buf.toString("utf8"));
  } catch (e) {
    return [`not valid JSON: ${e.message}`];
  }
  if (pack.schemaVersion !== 1) errors.push(`unknown schemaVersion ${pack.schemaVersion}`);
  if (!Array.isArray(pack.sites)) return [...errors, "sites must be an array"];
  if (pack.sites.length > MAX_SITES) errors.push(`too many sites: ${pack.sites.length}`);

  const selectorOK = (s) =>
    typeof s === "string" && s.trim() !== "" && s.length < MAX_SELECTOR && !FORBIDDEN.test(s);

  for (const s of pack.sites) {
    const id = s.id;
    if (!KNOWN_IDS.includes(id)) errors.push(`${id}: unknown site id`);
    for (const list of ["allowedHosts", "pathRules", "hideSelectors", "hideByText", "contentRules", "canaries"]) {
      const v = s[list];
      if (!Array.isArray(v)) errors.push(`${id}: ${list} must be an array`);
      else if (v.length > MAX_LIST) errors.push(`${id}: ${list} has ${v.length} entries, max ${MAX_LIST}`);
    }
    for (const r of s.pathRules ?? []) {
      try {
        new RegExp(r.pattern);
      } catch {
        errors.push(`${id}: regex does not compile: ${r.pattern}`);
      }
      if (r.action === "redirect" && !(typeof r.to === "string" && r.to.startsWith("/"))) {
        errors.push(`${id}: redirect target must start with /: ${r.to}`);
      }
      if (r.action !== "redirect" && r.action !== "block") errors.push(`${id}: bad action ${r.action}`);
    }
    const selectors = [...(s.hideSelectors ?? []), ...(s.canaries ?? [])];
    for (const t of s.hideByText ?? []) {
      selectors.push(t.closest);
      if (t.within !== undefined && t.within !== null) selectors.push(t.within);
    }
    for (const sel of selectors) {
      if (!selectorOK(sel)) errors.push(`${id}: invalid selector: ${JSON.stringify(sel)}`);
    }
    let host = null;
    try {
      const u = new URL(s.homeURL);
      if (u.protocol === "https:") host = u.hostname.toLowerCase();
    } catch {}
    if (!host) {
      errors.push(`${id}: homeURL must be https: ${s.homeURL}`);
    } else if (!(s.allowedHosts ?? []).some((a) => host === a.toLowerCase() || host.endsWith("." + a.toLowerCase()))) {
      errors.push(`${id}: homeURL host ${host} not covered by allowedHosts`);
    }
  }
  return errors;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const file = process.argv[2];
  if (!file) {
    console.error("usage: validate-rules.mjs <rulepack.json>");
    process.exit(2);
  }
  const errors = validate(readFileSync(file));
  if (errors.length) {
    for (const e of errors) console.error(`FAIL: ${e}`);
    process.exit(1);
  }
  console.log(`${file}: OK`);
}
