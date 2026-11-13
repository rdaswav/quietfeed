import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { JSDOM } from "jsdom";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const runtimeSource = readFileSync(join(root, "web", "runtime.js"), "utf8");
const pack = JSON.parse(readFileSync(join(root, "rules", "rulepack.json"), "utf8"));
const fixture = (name) => readFileSync(join(root, "web", "fixtures", name), "utf8");
const site = (id) => pack.sites.find((s) => s.id === id);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function load({ siteId, html, url, config = {}, preHooks = {} }) {
  const dom = new JSDOM(fixture(html), { url, runScripts: "outside-only", pretendToBeVisual: true });
  const { window } = dom;
  const messages = [];
  window.webkit = { messageHandlers: { quietfeed: { postMessage: (m) => messages.push(JSON.parse(JSON.stringify(m))) } } };
  const s = site(siteId);
  const cfg = {
    siteId,
    pathRules: s.pathRules,
    hideSelectors: s.hideSelectors,
    hideByText: s.hideByText,
    canaries: s.canaries,
    test: true,
    healthDelayMs: 30,
    ...config,
  };
  window.__QF_TEST__ = { ...preHooks };
  window.eval(`window.__QF_CONFIG__ = ${JSON.stringify(cfg)};\n${runtimeSource}`);
  return { dom, window, document: window.document, messages, cfg };
}

const hidden = (window, el) => window.getComputedStyle(el).display === "none";

test("style element is created with all selectors", () => {
  const { document, cfg } = load({ siteId: "youtube", html: "youtube-home.html", url: "https://m.youtube.com/" });
  const style = document.getElementById("qf-style");
  assert.ok(style, "style element exists");
  assert.equal(style.parentNode, document.documentElement);
  for (const sel of cfg.hideSelectors) assert.ok(style.textContent.includes(sel), sel);
  assert.ok(style.textContent.includes("[data-qf-hidden]"));
  assert.ok(style.textContent.includes("display: none !important"));
});

test("selectors hide the shelf and leave normal videos", () => {
  const { window, document } = load({ siteId: "youtube", html: "youtube-home.html", url: "https://m.youtube.com/" });
  assert.ok(hidden(window, document.getElementById("shorts-shelf")));
  assert.ok(!hidden(window, document.getElementById("normal-video")));
  assert.ok(!hidden(window, document.getElementById("canary")));
});

test("text rule hides the right ancestor and only that one", async () => {
  const { window, document } = load({ siteId: "instagram", html: "instagram-feed.html", url: "https://www.instagram.com/" });
  await sleep(400);
  const suggested = document.getElementById("post-suggested");
  assert.equal(suggested.getAttribute("data-qf-hidden"), "1");
  assert.ok(hidden(window, suggested));
  for (const id of ["post-1", "post-2"]) {
    assert.ok(!document.getElementById(id).hasAttribute("data-qf-hidden"), id);
    assert.ok(!hidden(window, document.getElementById(id)), id);
  }
  assert.ok(!document.getElementById("canary-main").hasAttribute("data-qf-hidden"));
  assert.equal(document.querySelectorAll("[data-qf-hidden]").length, 1);
});

test("text rule uses the within selector and closest for the pivot bar", async () => {
  const { document } = load({ siteId: "youtube", html: "youtube-home.html", url: "https://m.youtube.com/" });
  await sleep(400);
  assert.equal(document.getElementById("pivot-shorts").getAttribute("data-qf-hidden"), "1");
  assert.ok(!document.getElementById("pivot-home").hasAttribute("data-qf-hidden"));
  assert.ok(!document.getElementById("pivot-subs").hasAttribute("data-qf-hidden"));
});

test("facebook rules hide feed units, the open app bar and the reels tab", async () => {
  const { window, document } = load({ siteId: "facebook", html: "facebook-feed.html", url: "https://m.facebook.com/" });
  await sleep(400);
  assert.equal(document.getElementById("unit-reels").getAttribute("data-qf-hidden"), "1");
  assert.equal(document.getElementById("unit-people").getAttribute("data-qf-hidden"), "1");
  assert.equal(document.getElementById("open-app-bar").getAttribute("data-qf-hidden"), "1");
  assert.ok(hidden(window, document.getElementById("tab-reels")));
  assert.ok(!document.getElementById("post-1").hasAttribute("data-qf-hidden"));
  assert.ok(!document.getElementById("post-2").hasAttribute("data-qf-hidden"));
  assert.ok(!document.getElementById("tabs").hasAttribute("data-qf-hidden"));
  assert.ok(!hidden(window, document.getElementById("tab-home")));
  assert.ok(!hidden(window, document.getElementById("composer")));
});

test("content added after load is hidden within 500 ms", async () => {
  const { window, document } = load({ siteId: "instagram", html: "instagram-feed.html", url: "https://www.instagram.com/" });
  await sleep(400);
  const art = document.createElement("article");
  art.id = "late";
  art.innerHTML = "<div><span>  suggested FOR you </span></div><div>late arrival</div>";
  document.getElementById("canary-main").appendChild(art);
  const added = Date.now();
  await sleep(450);
  assert.ok(Date.now() - added < 500 + 100);
  assert.equal(art.getAttribute("data-qf-hidden"), "1");
  assert.ok(hidden(window, art));
});

test("pushState to a blocked path triggers a redirect", () => {
  const replaced = [];
  const { window } = load({
    siteId: "instagram",
    html: "instagram-feed.html",
    url: "https://www.instagram.com/",
    preHooks: { replace: (u) => replaced.push(u) },
  });
  assert.deepEqual(replaced, []);
  window.history.pushState({}, "", "/reels/");
  assert.deepEqual(replaced, ["/"]);
  window.history.pushState({}, "", "/reel/abc/");
  assert.deepEqual(replaced, ["/"], "allowed path does not redirect");
});

test("youtube shorts path redirects to watch with the id", () => {
  const replaced = [];
  const { window } = load({
    siteId: "youtube",
    html: "youtube-home.html",
    url: "https://m.youtube.com/",
    preHooks: { replace: (u) => replaced.push(u) },
  });
  window.history.replaceState({}, "", "/shorts/abc_123");
  assert.deepEqual(replaced, ["/watch?v=abc_123"]);
});

test("health message has the documented shape", async () => {
  const { messages } = load({ siteId: "youtube", html: "youtube-home.html", url: "https://m.youtube.com/" });
  await sleep(150);
  assert.equal(messages.length, 1);
  const m = messages[0];
  assert.equal(m.type, "health");
  assert.equal(m.path, "/");
  assert.deepEqual(m.canaries, [true]);
  assert.equal(typeof m.hideCounts, "object");
  assert.equal(m.hideCounts["ytm-reel-shelf-renderer"], 1);
  assert.equal(m.hideCounts["grid-shelf-view-model"], 0);
});

test("health reports a missing canary as false", async () => {
  const { messages } = load({
    siteId: "youtube",
    html: "youtube-home.html",
    url: "https://m.youtube.com/",
    config: { canaries: ["ytm-pivot-bar-renderer", "#nope"] },
  });
  await sleep(150);
  assert.deepEqual(messages[0].canaries, [true, false]);
});

test("health is sent again after a path change", async () => {
  const { window, messages } = load({ siteId: "youtube", html: "youtube-home.html", url: "https://m.youtube.com/" });
  await sleep(150);
  window.history.pushState({}, "", "/feed/subscriptions");
  await sleep(150);
  assert.equal(messages.length, 2);
  assert.equal(messages[1].path, "/feed/subscriptions");
});

test("running the script twice does nothing the second time", async () => {
  const replaced = [];
  const { window, document, messages } = load({
    siteId: "instagram",
    html: "instagram-feed.html",
    url: "https://www.instagram.com/",
    preHooks: { replace: (u) => replaced.push(u) },
  });
  const pushStateBefore = window.history.pushState;
  window.eval(runtimeSource);
  assert.equal(document.querySelectorAll("#qf-style").length, 1);
  assert.equal(window.history.pushState, pushStateBefore);
  window.history.pushState({}, "", "/reels/");
  assert.deepEqual(replaced, ["/"], "redirect fires once, not twice");
  await sleep(150);
  assert.equal(messages.filter((m) => m.path === "/reels/").length, 1);
});
