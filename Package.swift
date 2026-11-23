// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevNotify",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DevNotify", targets: ["DevNotify"])],
    targets: [
        .executableTarget(name: "DevNotify"),
        // SwiftPM's swiftbuild backend intermittently omits the Swift Testing macro plugin path with Command Line Tools only,
        // failing with "plugin for module 'TestingMacros' not found". Passing it explicitly keeps `swift test` deterministic.
        .testTarget(name: "DevNotifyTests", dependencies: ["DevNotify"], swiftSettings: [.unsafeFlags([
            "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
        ])])
    ],
    swiftLanguageModes: [.v5]
)
