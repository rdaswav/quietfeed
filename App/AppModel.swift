import Foundation
import Observation
import QuietFeedCore

@Observable
final class AppModel {
    private(set) var pack: RulePack?
    private(set) var loadError: String?
    /// Latest health report per site id, from the injected runtime.
    private(set) var healthReports: [String: HealthReport] = [:]

    var sites: [SiteRules] { pack?.sites ?? [] }

    init(bundle: Bundle = .main) {
        loadBundledPack(from: bundle)
    }

    func recordHealth(_ report: HealthReport, for siteId: String) {
        healthReports[siteId] = report
    }

    private func loadBundledPack(from bundle: Bundle) {
        guard let url = bundle.url(forResource: "rulepack", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            loadError = "The bundled rules are missing."
            return
        }
        switch RulePackValidator.validate(data) {
        case .success(let pack): self.pack = pack
        case .failure(let error): loadError = "The bundled rules are invalid: \(error)"
        }
    }
}
