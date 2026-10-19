// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnarwalCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SnarwalCore", targets: ["SnarwalCore"]),
    ],
    targets: [
        .target(name: "SnarwalCore"),
        .testTarget(name: "SnarwalCoreTests", dependencies: ["SnarwalCore"]),
    ],
    swiftLanguageModes: [.v5]
)
