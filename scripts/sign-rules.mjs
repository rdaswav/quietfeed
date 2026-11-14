#!/usr/bin/env node
// Signs rules/rulepack.json into the envelope the app verifies (Architecture 4.5).
// Usage: RULES_SIGNING_KEY="$(cat key.pem)" node scripts/sign-rules.mjs [--in file] [--out file] [--key-id k1]
// The private key comes only from the environment variable RULES_SIGNING_KEY (the PEM text itself).
// It is never printed. A pack that fails validation is never signed.
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { validate } from "./validate-rules.mjs";

/** Returns the envelope object for the given pack bytes. Throws if the pack is invalid or the key is bad. */
export function signPack(packBytes, privateKeyPem, keyId = "k1") {
  const errors = validate(packBytes);
  if (errors.length) throw new Error(`refusing to sign an invalid pack: ${errors.join("; ")}`);
  if (!privateKeyPem) throw new Error("no signing key: set RULES_SIGNING_KEY to the private key PEM");
  const key = createPrivateKey(privateKeyPem);
  const signature = sign(null, packBytes, key);
  return {
    keyId,
    payload: Buffer.from(packBytes).toString("base64"),
    signature: signature.toString("base64"),
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const opt = (name, fallback) => {
    const i = args.indexOf(name);
    return i === -1 ? fallback : args[i + 1];
  };
  try {
    const bytes = readFileSync(opt("--in", "rules/rulepack.json"));
    const envelope = signPack(bytes, process.env.RULES_SIGNING_KEY, opt("--key-id", "k1"));
    const text = JSON.stringify(envelope) + "\n";
    const out = opt("--out", null);
    if (out) writeFileSync(out, text);
    else process.stdout.write(text);
  } catch (e) {
    console.error(`sign-rules: ${e.message}`);
    process.exit(1);
  }
}
