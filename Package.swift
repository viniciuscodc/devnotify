// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevNotify",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DevNotify", targets: ["DevNotify"])],
    targets: [
        .executableTarget(name: "DevNotify"),
        .testTarget(name: "DevNotifyTests", dependencies: ["DevNotify"])
    ],
    swiftLanguageModes: [.v5]
)
