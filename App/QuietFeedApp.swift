import SwiftUI
import QuietFeedCore

@main
struct QuietFeedApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
        }
    }
}
