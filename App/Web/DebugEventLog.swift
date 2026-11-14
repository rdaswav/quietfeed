#if DEBUG
import Foundation

/// Debug builds only. Appends one line per web event (main page navigations, redirects we cause, the
/// web process being killed) to Documents/webview-events.log so odd behaviour can be read back.
/// Only paths are written, never query strings, page text or names.
enum DebugEventLog {
    private static let queue = DispatchQueue(label: "quietfeed.eventlog")

    static func record(_ siteId: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(siteId) \(message)\n"
        queue.async {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("webview-events.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    static func path(_ url: URL?) -> String { url?.path ?? "?" }
}
#endif
