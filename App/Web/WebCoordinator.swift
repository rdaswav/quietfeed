import Foundation
import WebKit

/// What the injected runtime reports about page health. Built from untrusted page data,
/// so every field is type-checked before use.
struct HealthReport: Equatable {
    var path: String
    var canaries: [Bool]
    var hideCounts: [String: Int]

    init?(body: Any) {
        guard let dict = body as? [String: Any],
              dict["type"] as? String == "health",
              let path = dict["path"] as? String,
              let canaries = dict["canaries"] as? [Any],
              let counts = dict["hideCounts"] as? [String: Any] else { return nil }
        var flags: [Bool] = []
        for c in canaries {
            guard let b = c as? Bool else { return nil }
            flags.append(b)
        }
        var hide: [String: Int] = [:]
        for (k, v) in counts {
            guard let n = v as? Int else { return nil }
            hide[k] = n
        }
        self.path = path
        self.canaries = flags
        self.hideCounts = hide
    }
}

/// Avoids the retain cycle WKUserContentController creates with its message handlers.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

final class WebCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let siteId: String
    var onHealth: (String, HealthReport) -> Void

    init(siteId: String, onHealth: @escaping (String, HealthReport) -> Void) {
        self.siteId = siteId
        self.onHealth = onHealth
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "quietfeed", let report = HealthReport(body: message.body) else { return }
        onHealth(siteId, report)
    }
}
