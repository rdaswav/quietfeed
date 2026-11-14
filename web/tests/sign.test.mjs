import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createPublicKey, generateKeyPairSync, verify } from "node:crypto";
import { signPack } from "../../scripts/sign-rules.mjs";
import { rawPublicKey } from "../../scripts/gen-rules-key.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const pack = readFileSync(join(root, "rules", "rulepack.json"));
const pem = (k) => k.export({ type: "pkcs8", format: "pem" });
// SPKI prefix for a raw Ed25519 public key.
const fromRaw = (raw) =>
  createPublicKey({ key: Buffer.concat([Buffer.from("302a300506032b6570032100", "hex"), raw]), format: "der", type: "spki" });

test("a signed envelope verifies and carries the exact pack bytes", () => {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const env = signPack(pack, pem(privateKey), "k1");
  assert.deepEqual(Object.keys(env).sort(), ["keyId", "payload", "signature"]);
  assert.equal(env.keyId, "k1");
  const payload = Buffer.from(env.payload, "base64");
  assert.ok(payload.equals(pack));
  assert.ok(verify(null, payload, publicKey, Buffer.from(env.signature, "base64")));
  assert.ok(verify(null, payload, fromRaw(rawPublicKey(publicKey)), Buffer.from(env.signature, "base64")));
});

test("a changed payload no longer verifies", () => {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const env = signPack(pack, pem(privateKey));
  const changed = Buffer.from(pack);
  changed[changed.length - 3] ^= 1;
  assert.ok(!verify(null, changed, publicKey, Buffer.from(env.signature, "base64")));
});

test("an invalid pack is never signed", () => {
  const { privateKey } = generateKeyPairSync("ed25519");
  assert.throws(() => signPack(Buffer.from("{}"), pem(privateKey)), /refusing to sign/);
  assert.throws(() => signPack(Buffer.from("not json"), pem(privateKey)), /refusing to sign/);
});

test("a missing key is an error and says which variable to set", () => {
  assert.throws(() => signPack(pack, ""), /RULES_SIGNING_KEY/);
  assert.throws(() => signPack(pack, undefined), /RULES_SIGNING_KEY/);
});

test("the committed vector verifies in Node, as it does in Swift", () => {
  const v = JSON.parse(
    readFileSync(join(root, "Packages/QuietFeedCore/Tests/QuietFeedCoreTests/Fixtures/signed-vector.json"), "utf8"));
  const key = fromRaw(Buffer.from(v.publicKey, "base64"));
  assert.equal(Buffer.from(v.publicKey, "base64").length, 32);
  assert.ok(verify(null, Buffer.from(v.envelope.payload, "base64"), key, Buffer.from(v.envelope.signature, "base64")));
});
