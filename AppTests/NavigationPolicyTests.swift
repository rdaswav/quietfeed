import XCTest
import WebKit
import QuietFeedCore
@testable import QuietFeed

final class NavigationPolicyTests: XCTestCase {
    func testAllowUsesUniversalLinkSuppressingValue() {
        let allow = NavigationPolicyMapper.allowWithoutUniversalLinks
        XCTAssertEqual(allow.rawValue, WKNavigationActionPolicy.allow.rawValue + 2)
        XCTAssertEqual(NavigationPolicyMapper.actionPolicy(for: .allow), allow)
    }

    func testDecisionMapping() {
        let url = URL(string: "https://m.youtube.com/watch?v=a")!
        XCTAssertEqual(NavigationPolicyMapper.outcome(for: .allow), .allow)
        XCTAssertEqual(NavigationPolicyMapper.outcome(for: .cancel), .cancel)
        XCTAssertEqual(NavigationPolicyMapper.outcome(for: .openExternally), .cancelAndOpenExternally)
        XCTAssertEqual(NavigationPolicyMapper.outcome(for: .redirect(url)), .cancelAndLoad(url))
    }

    func testNonAllowOutcomesCancelTheNavigation() {
        let url = URL(string: "https://example.com/")!
        for outcome in [NavigationOutcome.cancel, .cancelAndOpenExternally, .cancelAndLoad(url)] {
            XCTAssertEqual(NavigationPolicyMapper.actionPolicy(for: outcome), .cancel)
        }
    }

    func testInfoPlistHasUsageStrings() {
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"] {
            XCTAssertFalse((Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "").isEmpty, key)
        }
    }
}
