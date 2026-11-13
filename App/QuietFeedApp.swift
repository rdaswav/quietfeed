import SwiftUI
import QuietFeedCore

@main
struct QuietFeedApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    /// The hosted unit tests launch the app; they must never reach the network.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
                .task { if !Self.isRunningTests { await model.refreshRules() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, !Self.isRunningTests {
                        model.reconcileShield()
                        Task { await model.refreshRulesIfDue() }
                    }
                }
        }
    }
}
