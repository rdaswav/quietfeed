(function () {
  "use strict";
  if (window.__QF_LOADED__) return;
  window.__QF_LOADED__ = true;

  var cfg = window.__QF_CONFIG__ || {};
  var pathRules = cfg.pathRules || [];
  var hideSelectors = cfg.hideSelectors || [];
  var hideByText = cfg.hideByText || [];
  var canaries = cfg.canaries || [];
  // Debug builds can switch parts off to find which one upsets a page: style, history, text, health.
  var off = window.__QF_DISABLE__ || [];
  function disabled(name) { return off.indexOf(name) !== -1; }
  var PASS_INTERVAL_MS = 250;
  var HEALTH_DELAY_MS = typeof cfg.healthDelayMs === "number" ? cfg.healthDelayMs : 3000;

  // 1. Style: hide by selector from first paint.
  function installStyle() {
    var root = document.documentElement;
    if (disabled("style") || !root || document.getElementById("qf-style")) return;
    var style = document.createElement("style");
    style.id = "qf-style";
    var css = "";
    if (hideSelectors.length) css += hideSelectors.join(",\n") + " { display: none !important; }\n";
    // Whole posts and bars found by text are collapsed to nothing but kept rendered. Taking them out of
    // rendering with display: none made Instagram's feed lose its place and go blank on a real phone,
    // while a zero height box that is still there did not (tested on an iPhone, 2026-11-14).
    // A debug build can set window.__QF_HIDE_MODE__ = "none" to compare with the old behaviour.
    if (window.__QF_HIDE_MODE__ === "none") {
      css += "[data-qf-hidden] { display: none !important; }\n";
    } else {
      css += "[data-qf-hidden] { height: 0 !important; min-height: 0 !important; overflow: hidden !important;" +
        " margin: 0 !important; padding: 0 !important; border: 0 !important; }\n";
    }
    style.textContent = css;
    root.appendChild(style);
  }

  // 2. Path guard.
  function doReplace(url) {
    var t = window.__QF_TEST__;
    if (t && typeof t.replace === "function") return t.replace(url);
    location.replace(url);
  }

  function substitute(to, m) {
    return to.replace(/\$([1-9])/g, function (_, n) {
      return m[Number(n)] === undefined ? "" : m[Number(n)];
    });
  }

  function checkPath() {
    var path = location.pathname;
    for (var i = 0; i < pathRules.length; i++) {
      var rule = pathRules[i];
      var re;
      try { re = new RegExp(rule.pattern); } catch (e) { continue; }
      var m = re.exec(path);
      if (!m) continue;
      if (rule.action === "redirect" && typeof rule.to === "string") {
        var target = substitute(rule.to, m);
        if (target !== path + location.search) doReplace(target);
      } else if (rule.action === "block") {
        history.back();
        setTimeout(function () {
          for (var j = 0; j < pathRules.length; j++) {
            if (pathRules[j].action === "block" && new RegExp(pathRules[j].pattern).test(location.pathname)) {
              doReplace("/");
              return;
            }
          }
        }, 300);
      }
      return;
    }
  }

  // 3. Text hiding.
  // The first pass looks at the whole page. After that only content that was added or changed is
  // looked at, so the cost follows what the page changes and not how long the feed has grown.
  var lastPass = 0;
  var passTimer = null;
  var fullScan = true;
  var pendingRoots = [];
  var MAX_PENDING = 150;
  var examined = 0;

  var rules = hideByText.map(function (rule) {
    return {
      want: String(rule.text).trim().toLowerCase(),
      within: rule.within || "span, h2, h3, h4",
      closest: rule.closest
    };
  });

  function checkElement(el, rule) {
    examined++;
    if ((el.textContent || "").trim().toLowerCase() !== rule.want) return;
    var target;
    try { target = el.closest(rule.closest); } catch (e) { target = null; }
    if (target && !target.hasAttribute("data-qf-hidden")) target.setAttribute("data-qf-hidden", "1");
  }

  function scanRoot(root) {
    for (var i = 0; i < rules.length; i++) {
      var rule = rules[i];
      var nodes;
      try {
        if (root.matches && root.matches(rule.within)) checkElement(root, rule);
        nodes = root.querySelectorAll(rule.within);
      } catch (e) { continue; }
      for (var j = 0; j < nodes.length; j++) checkElement(nodes[j], rule);
    }
  }

  function runTextPass() {
    passTimer = null;
    lastPass = Date.now();
    examined = 0;
    var roots;
    if (fullScan || pendingRoots.length > MAX_PENDING) {
      roots = [document.documentElement];
      fullScan = false;
    } else {
      roots = pendingRoots;
    }
    pendingRoots = [];
    for (var i = 0; i < roots.length; i++) {
      var root = roots[i];
      if (root && root.isConnected) scanRoot(root);
    }
    return examined;
  }

  function schedulePass() {
    if (passTimer !== null) return;
    var wait = Math.max(0, PASS_INTERVAL_MS - (Date.now() - lastPass));
    passTimer = setTimeout(runTextPass, wait);
  }

  function noteChanges(records) {
    for (var i = 0; i < records.length; i++) {
      var rec = records[i];
      if (rec.type === "characterData") {
        if (rec.target.parentElement) pendingRoots.push(rec.target.parentElement);
        continue;
      }
      for (var j = 0; j < rec.addedNodes.length; j++) {
        var n = rec.addedNodes[j];
        var el = n.nodeType === 1 ? n : n.parentElement;
        if (el) pendingRoots.push(el);
      }
    }
    schedulePass();
  }

  // 4. Health.
  var healthTimer = null;

  function sendHealth() {
    healthTimer = null;
    var counts = {};
    for (var i = 0; i < hideSelectors.length; i++) {
      try { counts[hideSelectors[i]] = document.querySelectorAll(hideSelectors[i]).length; }
      catch (e) { counts[hideSelectors[i]] = 0; }
    }
    var found = canaries.map(function (sel) {
      try { return document.querySelector(sel) !== null; } catch (e) { return false; }
    });
    // How many things were hidden on this page: selector hits plus posts and bars hidden by text.
    var hiddenCount = document.querySelectorAll("[data-qf-hidden]").length;
    for (var key in counts) hiddenCount += counts[key];
    var msg = { type: "health", path: location.pathname, canaries: found, hideCounts: counts, hiddenCount: hiddenCount };
    try {
      window.webkit.messageHandlers.quietfeed.postMessage(msg);
    } catch (e) { /* not running inside the app */ }
  }

  function scheduleHealth() {
    if (disabled("health")) return;
    if (healthTimer !== null) clearTimeout(healthTimer);
    healthTimer = setTimeout(sendHealth, HEALTH_DELAY_MS);
  }

  function onPathChange() {
    checkPath();
    schedulePass();
    scheduleHealth();
  }

  // Wire up.
  installStyle();
  checkPath();

  if (!disabled("history")) ["pushState", "replaceState"].forEach(function (name) {
    var orig = history[name];
    history[name] = function () {
      var r = orig.apply(this, arguments);
      onPathChange();
      return r;
    };
  });
  if (!disabled("history")) window.addEventListener("popstate", onPathChange);

  if (!disabled("text") && document.documentElement) {
    new MutationObserver(noteChanges).observe(document.documentElement, {
      childList: true, subtree: true, characterData: true
    });
  }
  if (!disabled("text")) schedulePass();

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      installStyle();
      fullScan = true;
      if (!disabled("text")) schedulePass();
      scheduleHealth();
    });
  } else {
    scheduleHealth();
  }

  // 5. Test hooks.
  if (cfg.test === true) {
    var hooks = window.__QF_TEST__ || {};
    hooks.checkPath = checkPath;
    hooks.runTextPass = function () { fullScan = true; return runTextPass(); };
    hooks.lastExamined = function () { return examined; };
    hooks.sendHealth = sendHealth;
    window.__QF_TEST__ = hooks;
  }
})();
