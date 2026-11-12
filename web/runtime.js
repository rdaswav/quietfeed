(function () {
  "use strict";
  if (window.__QF_LOADED__) return;
  window.__QF_LOADED__ = true;

  var cfg = window.__QF_CONFIG__ || {};
  var pathRules = cfg.pathRules || [];
  var hideSelectors = cfg.hideSelectors || [];
  var hideByText = cfg.hideByText || [];
  var canaries = cfg.canaries || [];
  var PASS_INTERVAL_MS = 250;
  var HEALTH_DELAY_MS = typeof cfg.healthDelayMs === "number" ? cfg.healthDelayMs : 3000;

  // 1. Style: hide by selector from first paint.
  function installStyle() {
    var root = document.documentElement;
    if (!root || document.getElementById("qf-style")) return;
    var style = document.createElement("style");
    style.id = "qf-style";
    var sels = hideSelectors.concat(["[data-qf-hidden]"]);
    style.textContent = sels.join(",\n") + " { display: none !important; }";
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
  var lastPass = 0;
  var passTimer = null;

  function runTextPass() {
    passTimer = null;
    lastPass = Date.now();
    for (var i = 0; i < hideByText.length; i++) {
      var rule = hideByText[i];
      var want = String(rule.text).trim().toLowerCase();
      var nodes;
      try { nodes = document.querySelectorAll(rule.within || "span, h2, h3, h4"); } catch (e) { continue; }
      for (var j = 0; j < nodes.length; j++) {
        var el = nodes[j];
        if ((el.textContent || "").trim().toLowerCase() !== want) continue;
        var target;
        try { target = el.closest(rule.closest); } catch (e) { target = null; }
        if (target && !target.hasAttribute("data-qf-hidden")) target.setAttribute("data-qf-hidden", "1");
      }
    }
  }

  function schedulePass() {
    if (passTimer !== null) return;
    var wait = Math.max(0, PASS_INTERVAL_MS - (Date.now() - lastPass));
    passTimer = setTimeout(runTextPass, wait);
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
    var msg = { type: "health", path: location.pathname, canaries: found, hideCounts: counts };
    try {
      window.webkit.messageHandlers.quietfeed.postMessage(msg);
    } catch (e) { /* not running inside the app */ }
  }

  function scheduleHealth() {
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

  ["pushState", "replaceState"].forEach(function (name) {
    var orig = history[name];
    history[name] = function () {
      var r = orig.apply(this, arguments);
      onPathChange();
      return r;
    };
  });
  window.addEventListener("popstate", onPathChange);

  if (document.documentElement) {
    new MutationObserver(schedulePass).observe(document.documentElement, { childList: true, subtree: true });
  }
  schedulePass();

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      installStyle();
      schedulePass();
      scheduleHealth();
    });
  } else {
    scheduleHealth();
  }

  // 5. Test hooks.
  if (cfg.test === true) {
    var hooks = window.__QF_TEST__ || {};
    hooks.checkPath = checkPath;
    hooks.runTextPass = runTextPass;
    hooks.sendHealth = sendHealth;
    window.__QF_TEST__ = hooks;
  }
})();
