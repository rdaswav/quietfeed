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

    /// Script that finds the site's own tab bar and hides it, and remembers the profile link.
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
            if (!window.__qfProfileHref) {
              var links = b.querySelectorAll("a[href]");
              for (var i = 0; i < links.length; i++) {
                var h = links[i].getAttribute("href") || "";
                if (h.charAt(0) === "/" && known.indexOf(h) < 0 && h.indexOf("/accounts") !== 0) {
                  window.__qfProfileHref = h; break;
                }
              }
            }
            b.style.setProperty("display", "none", "important");
          }
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
