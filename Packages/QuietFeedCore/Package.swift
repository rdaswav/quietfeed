// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QuietFeedCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "QuietFeedCore", targets: ["QuietFeedCore"])],
    targets: [
        .target(name: "QuietFeedCore"),
        .testTarget(name: "QuietFeedCoreTests", dependencies: ["QuietFeedCore"]),
    ],
    swiftLanguageModes: [.v5]
)
