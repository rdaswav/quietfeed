#!/usr/bin/env node
// Makes the Ed25519 key that signs the official rule packs (Architecture 4.5). Human-run, once.
// Usage: node scripts/gen-rules-key.mjs <private-key-path>
// Writes the private key as a PEM file (mode 600, never overwritten) and prints the PUBLIC key as
// base64 of the raw 32 bytes. The public key goes in the app; the private key goes in a password
// manager and in the GitHub secret RULES_SIGNING_KEY. It must never be committed.
import { generateKeyPairSync } from "node:crypto";
import { existsSync, writeFileSync } from "node:fs";

/** Raw 32 byte public key from a Node KeyObject. */
export function rawPublicKey(publicKey) {
  const der = publicKey.export({ type: "spki", format: "der" });
  return der.subarray(der.length - 32);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const path = process.argv[2];
  if (!path) {
    console.error("usage: gen-rules-key.mjs <private-key-path>");
    process.exit(2);
  }
  if (existsSync(path)) {
    console.error(`${path} already exists, not overwriting it`);
    process.exit(1);
  }
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  writeFileSync(path, privateKey.export({ type: "pkcs8", format: "pem" }), { mode: 0o600 });
  console.log(`private key written to ${path} (keep it secret, never commit it)`);
  console.log(`PUBLIC KEY k1: ${rawPublicKey(publicKey).toString("base64")}`);
}
