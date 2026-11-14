import Foundation

/// The app's own bottom tab bar for a site. The site's native bar is hidden and these buttons
/// take its place, so the feed keeps its Home and Messages but never shows Reels or Explore.
/// This lives in the app, not the rule pack: a changed tab list is a design choice, not a breakage.
struct SiteNav {
    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        let symbol: String
        /// A path on the site's own host. `nil` with `profile` set means "the signed-in profile".
        let path: String?
        var isProfile = false
        /// True when the current page path belongs to this tab.
        let matches: (String) -> Bool

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    }

    let items: [Item]
    /// A link that only exists inside the site's own tab bar. The bar is found from it.
    let probeSelector: String
    /// Extra links in the site's bar that are not in `items` are ignored.
    let allowsProfile: Bool

    static func forSite(_ siteId: String) -> SiteNav? {
        switch siteId {
        case "instagram":
            return SiteNav(
                items: [
                    Item(id: "home", label: "Home", symbol: "house", path: "/",
                         matches: { $0 == "/" || $0 == "" }),
                    Item(id: "messages", label: "Messages", symbol: "paperplane", path: "/direct/inbox/",
                         matches: { $0.hasPrefix("/direct") }),
                    Item(id: "activity", label: "Activity", symbol: "heart", path: "/notifications/",
                         matches: { $0.hasPrefix("/notifications") }),
                    Item(id: "profile", label: "Profile", symbol: "person.crop.circle", path: nil, isProfile: true,
                         matches: { _ in false }),
                ],
                probeSelector: "a[href=\"/direct/inbox/\"]",
                allowsProfile: true)
        case "youtube":
            return SiteNav(
                items: [
                    Item(id: "home", label: "Home", symbol: "house", path: "/",
                         matches: { $0 == "/" || $0 == "" }),
                    Item(id: "subs", label: "Subscriptions", symbol: "rectangle.stack", path: "/feed/subscriptions",
                         matches: { $0.hasPrefix("/feed/subscriptions") }),
                    Item(id: "you", label: "You", symbol: "person.crop.circle", path: "/feed/you",
                         matches: { $0.hasPrefix("/feed/you") || $0.hasPrefix("/feed/library") }),
                ],
                probeSelector: "ytm-pivot-bar-renderer",
                allowsProfile: false)
        default:
            return nil
        }
    }

    /// Script that finds the site's own tab bar and hides it. Its Profile tab is clicked from code, since it may not be a plain link.
    /// It runs at document end and again whenever the page changes, because these sites rebuild the bar.
    var hideScript: String {
        let probe = probeSelector.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (function () {
          if (window.__qfNav) return;
          window.__qfNav = true;
          var probe = "\(probe)";
          var known = ["/", "/direct/inbox/", "/notifications/", "/reels/", "/explore/", "/feed/subscriptions", "/feed/you"];
          function bar() {
            var link = document.querySelector(probe);
            if (!link) return null;
            var el = link, found = null;
            while (el && el !== document.body && el !== document.documentElement) {
              var cs = getComputedStyle(el);
              var r = el.getBoundingClientRect();
              if ((cs.position === "fixed" || cs.position === "sticky") &&
                  r.width >= window.innerWidth * 0.9 && r.bottom >= window.innerHeight - 4) { found = el; break; }
              el = el.parentElement;
            }
            if (!found && link.matches("ytm-pivot-bar-renderer")) found = link;
            return found;
          }
          function run() {
            var b = bar();
            if (!b) return;
            window.__qfBar = b;
            b.style.setProperty("display", "none", "important");
          }
          // Goes to a path the way a tap on the site's own link would, so the page swaps its content
          // without a full reload. Returns false when the page has no such link.
          window.__qfGo = function (path) {
            var sel = 'a[href="' + path + '"]';
            var a = document.querySelector(sel);
            if (!a && path.length > 1) a = document.querySelector('a[href="' + path.replace(/\\/$/, "") + '"]');
            if (!a) return false;
            a.click();
            return true;
          };
          window.__qfOpenProfile = function () {
            var b = window.__qfBar;
            if (!b) return false;
            var items = b.querySelectorAll('a, [role="link"], [role="button"], button');
            var pick = null;
            for (var i = 0; i < items.length; i++) {
              var img = items[i].querySelector("img");
              if (img && /profile/i.test(img.getAttribute("alt") || "")) { pick = items[i]; break; }
            }
            if (!pick && items.length) pick = items[items.length - 1];
            if (!pick) return false;
            pick.click();
            return true;
          };
          var pending = false;
          new MutationObserver(function () {
            if (pending) return;
            pending = true;
            setTimeout(function () { pending = false; run(); }, 150);
          }).observe(document.documentElement, { childList: true, subtree: true });
          run();
        })();
        """
    }
}
