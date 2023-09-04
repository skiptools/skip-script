// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "skip-script",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
    products: [
        .library(name: "SkipScript", targets: ["SkipScript"]),
        .library(name: "SkipScriptKt", targets: ["SkipScriptKt"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "0.6.28"),
        .package(url: "https://source.skip.tools/skip-unit.git", from: "0.2.4"),
        .package(url: "https://source.skip.tools/skip-lib.git", from: "0.3.4"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.1.4"),
    ],
    targets: [
        .target(name: "SkipScript", plugins: [.plugin(name: "skippy", package: "skip")]),
        .target(name: "SkipScriptKt", dependencies: [
            "SkipScript",
            .product(name: "SkipUnitKt", package: "skip-unit"),
            .product(name: "SkipLibKt", package: "skip-lib"),
            .product(name: "SkipFoundationKt", package: "skip-foundation"),
        ], resources: [.process("Skip")], plugins: [.plugin(name: "transpile", package: "skip")]),
        .testTarget(name: "SkipScriptTests", dependencies: [
            "SkipScript"
        ], plugins: [.plugin(name: "skippy", package: "skip")]),
        .testTarget(name: "SkipScriptKtTests", dependencies: [
            "SkipScriptKt",
            .product(name: "SkipUnit", package: "skip-unit"),
        ], resources: [.process("Skip")], plugins: [.plugin(name: "transpile", package: "skip")]),
    ]
)
