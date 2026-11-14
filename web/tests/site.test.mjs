import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { markdownToHtml, inline } from "../../scripts/build-site.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

test("markdown subset converts to safe html", () => {
  const html = markdownToHtml("# Title\n\nSome **bold** and a [link](https://example.com).\n\n## Part\n\n- one\n- two <b>\n");
  assert.ok(html.includes("<h1>Title</h1>"));
  assert.ok(html.includes("<strong>bold</strong>"));
  assert.ok(html.includes('<a href="https://example.com">link</a>'));
  assert.ok(html.includes("<h2>Part</h2>"));
  assert.ok(html.includes("<li>two &lt;b&gt;</li>"), "raw html in the source is escaped");
});

test("only http and https links are made into anchors", () => {
  assert.ok(!inline("[x](javascript:alert(1))").includes("<a "));
});

test("the privacy policy converts with every section and no leftover markdown", () => {
  const html = markdownToHtml(readFileSync(join(root, "docs", "PRIVACY.md"), "utf8"));
  for (const heading of ["What stays on your phone", "What the app connects to", "Permissions", "Children"]) {
    assert.ok(html.includes(`<h2>${heading}</h2>`), heading);
  }
  assert.ok(!html.includes("**"));
  assert.ok(!/\]\(http/.test(html));
});

test("the landing page is self contained: no scripts and no requests to other sites for assets", () => {
  const page = readFileSync(join(root, "site", "index.html"), "utf8");
  assert.ok(!/<script/i.test(page));
  const external = [...page.matchAll(/(?:src|href)="(https?:\/\/[^"]+)"/g)].map((m) => m[1]);
  for (const url of external) {
    assert.ok(url.startsWith("https://github.com/rdaswav/quietfeed") || url.startsWith("https://rdaswav.github.io/quietfeed/"), url);
  }
  assert.ok(!/fonts\.googleapis|googletagmanager|analytics/i.test(page));
});

test("the landing page keeps the honest claims", () => {
  const page = readFileSync(join(root, "site", "index.html"), "utf8");
  assert.ok(page.includes("Not affiliated with Instagram, YouTube, Facebook or Meta."));
  assert.ok(page.includes("Early and honest"));
  assert.ok(!/five words/i.test(page));
  assert.ok(!/\[TESTFLIGHT LINK\]/.test(page));
});
