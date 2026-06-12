// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InterlinedKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "InterlinedKit",
            targets: ["InterlinedKit"]
        )
    ],
    targets: [
        .target(
            name: "InterlinedKit",
            path: "Sources/InterlinedKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "InterlinedKitTests",
            dependencies: ["InterlinedKit"],
            path: "Tests/InterlinedKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
