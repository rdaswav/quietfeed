#if DEBUG
import SwiftUI
import WebKit

/// Debug builds only. Saves the structure of the current page (tags, roles, short UI labels, where things
/// sit and whether Quiet Feed hid them) so hide rules can be written against what a site really serves.
/// Post text, names and links to people are not written: text is kept only for short labels in the top
/// of the page and in fixed bars, and links are reduced to their first path word.
enum PageOutline {
    static let script = #"""
    (function () {
      var MAX = 2500, count = 0, out = [];
      var SAFE = {reel:1,reels:1,watch:1,stories:1,story:1,groups:1,marketplace:1,gaming:1,friends:1,messages:1,
        notifications:1,menu:1,bookmarks:1,search:1,video:1,videos:1,shorts:1,feed:1,explore:1,direct:1,home:1,
        hashtag:1,login:1,help:1,settings:1,pages:1,events:1,saved:1,profile:1,photo:1,photos:1,posts:1,
        permalink:1,share:1,results:1,hashtag:1,accounts:1,reels_tab:1};
      function href(h) {
        try {
          var u = new URL(h, location.href);
          if (u.host !== location.host) return "(external)";
          var seg = u.pathname.split("/").filter(Boolean), first = (seg[0] || "").toLowerCase();
          return "/" + (SAFE[first] ? first : "*") + (seg.length > 1 ? "/..." : "");
        } catch (e) { return "?"; }
      }
      function r10(n) { return Math.round(n / 10) * 10; }
      // Known interface phrases. Their text is recorded wherever they appear; other text never is.
      var UI = ["reels","reels and short videos","short videos","suggested for you","suggested","people you may know",
        "open app","open facebook","open instagram","open youtube","use the app","get the app","sponsored","watch","video",
        "marketplace","follow","join","add friend","not now","install","shorts","explore","home","friends","messenger",
        "notifications","menu","create story","what's on your mind?","photo","live","stories","groups","gaming","search",
        "see all","play","more","discover","suggested reels","suggested posts","suggested for you"];
      function ownText(el) {
        var t = "";
        for (var i = 0; i < el.childNodes.length; i++) if (el.childNodes[i].nodeType === 3) t += el.childNodes[i].nodeValue;
        return t.trim();
      }
      function entry(el, depth) {
        var tag = el.tagName.toLowerCase(), cs = getComputedStyle(el), r = el.getBoundingClientRect();
        var shown = cs.position === "fixed" || cs.position === "sticky" || (r.top < 260 && r.bottom > 0);
        var e = { d: depth, t: tag };
        var role = el.getAttribute("role"); if (role) e.role = role;
        var id = el.id; if (id && /^[A-Za-z_-]{1,30}$/.test(id)) e.id = id;
        var data = {}, any = false;
        for (var i = 0; i < el.attributes.length; i++) {
          var a = el.attributes[i];
          if (a.name.indexOf("data-") === 0 && a.name !== "data-qf-hidden" && /^[A-Za-z_-]{1,30}$/.test(a.value)) { data[a.name] = a.value; any = true; }
        }
        if (any) e.data = data;
        var aria = el.getAttribute("aria-label");
        if (aria) {
          var al = aria.toLowerCase().replace(/[,.:].*$/, "").trim();
          var keep = role === "tab" || role === "tablist" || (shown && aria.length <= 40) || UI.indexOf(al) !== -1;
          e.aria = keep ? aria : "(len " + aria.length + ")";
        }
        if (tag === "a") e.href = href(el.getAttribute("href") || "");
        var own = ownText(el);
        if (own) {
          var low = own.toLowerCase();
          if (UI.indexOf(low) !== -1 || (shown && cs.position === "fixed" && own.length <= 40)) e.text = own;
          else e.text = "(len " + own.length + ")";
        }
        e.box = [r10(r.top), r10(r.left), r10(r.width), r10(r.height)];
        if (el.hasAttribute("data-qf-hidden")) e.qfHidden = true;
        if (cs.display === "none") e.displayNone = true;
        if (cs.position === "fixed") e.fixed = true;
        return e;
      }
      function walk(el, depth) {
        if (count >= MAX || depth > 18) return;
        var tag = el.tagName.toLowerCase();
        if (tag === "script" || tag === "style" || tag === "noscript" || tag === "link" || tag === "meta") return;
        count++;
        var e = entry(el, depth);
        out.push(e);
        if (tag === "svg" || e.displayNone) return;
        for (var i = 0; i < el.children.length; i++) walk(el.children[i], depth + 1);
      }
      walk(document.body, 0);
      // Cost of looking at every span and heading, the way the old text pass did, three times over.
      var t0 = performance.now(), looked = 0;
      for (var rep = 0; rep < 3; rep++) {
        var all = document.querySelectorAll("span, h2, h3, h4");
        for (var k = 0; k < all.length; k++) { looked++; (all[k].textContent || "").trim().toLowerCase(); }
      }
      var ms = performance.now() - t0;
      // Which elements our rules hid, and how much of the page they cover.
      var hiddenList = [];
      var hs = document.querySelectorAll("[data-qf-hidden]");
      for (var h = 0; h < hs.length && h < 20; h++) {
        var he = hs[h], hr = he.getBoundingClientRect();
        var depth = 0; for (var p = he; p.parentElement; p = p.parentElement) depth++;
        hiddenList.push({ t: he.tagName.toLowerCase(), depth: depth, descendants: he.getElementsByTagName("*").length,
          box: [r10(hr.top), r10(hr.left), r10(hr.width), r10(hr.height)],
          parentTag: he.parentElement ? he.parentElement.tagName.toLowerCase() : null,
          siblings: he.parentElement ? he.parentElement.children.length : 0 });
      }
      return JSON.stringify({
        page: href(location.href), viewport: [innerWidth, innerHeight],
        truncated: count >= MAX,
        stats: {
          elements: document.getElementsByTagName("*").length,
          spans: document.getElementsByTagName("span").length,
          articles: document.getElementsByTagName("article").length,
          videos: document.getElementsByTagName("video").length,
          qfHidden: document.querySelectorAll("[data-qf-hidden]").length,
          fullScanMs: Math.round(ms * 10) / 10, scanned: looked,
          scrollY: Math.round(scrollY), docHeight: document.documentElement.scrollHeight,
          hiddenElements: hiddenList,
          appearance: {
            prefersDark: window.matchMedia("(prefers-color-scheme: dark)").matches,
            bodyBackground: getComputedStyle(document.body).backgroundColor,
            htmlBackground: getComputedStyle(document.documentElement).backgroundColor,
            htmlColorScheme: getComputedStyle(document.documentElement).colorScheme,
            metaColorScheme: (document.querySelector('meta[name="color-scheme"]') || {}).content || null,
            themeColor: (document.querySelector('meta[name="theme-color"]') || {}).content || null
          }
        },
        nodes: out
      });
    })()
    """#
}

extension BrowserController {
    /// Writes the outline to the app's Documents folder and returns a short message.
    @MainActor
    func savePageOutline(siteId: String) async -> String {
        guard let webView else { return "There is no page to save." }
        do {
            let result = try await webView.evaluateJavaScript(PageOutline.script)
            guard let json = result as? String else { return "The page gave no outline." }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let name = "outline-\(siteId)-\(Int(Date().timeIntervalSince1970)).json"
            try json.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            return "Saved \(name)"
        } catch {
            return "Could not save: \(error.localizedDescription)"
        }
    }
}

struct OutlineAlert: ViewModifier {
    @Binding var note: String?

    func body(content: Content) -> some View {
        content.alert("Page outline", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(note ?? "")
        }
    }
}
#endif
