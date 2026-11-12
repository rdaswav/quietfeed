import SafariServices
import UIKit

/// Shows an external (non-allowed host) link in an in-app Safari sheet.
enum ExternalLinkSheet {
    @MainActor
    static func present(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let top = topViewController() else { return }
        top.present(SFSafariViewController(url: url), animated: true)
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
