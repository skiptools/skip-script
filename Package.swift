// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "skip-script",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
    products: [
        .library(name: "SkipScript", targets: ["SkipScript"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "0.6.75"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.2.1"),
    ],
    targets: [
        .target(name: "SkipScript", dependencies: [.product(name: "SkipFoundation", package: "skip-foundation")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipScriptTests", dependencies: [
            "SkipScript",
            .product(name: "SkipTest", package: "skip")
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
