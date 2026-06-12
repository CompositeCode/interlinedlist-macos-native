// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InterlinedDomain",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "InterlinedDomain",
            targets: ["InterlinedDomain"]
        )
    ],
    dependencies: [
        .package(path: "../InterlinedKit")
    ],
    targets: [
        .target(
            name: "InterlinedDomain",
            dependencies: [
                .product(name: "InterlinedKit", package: "InterlinedKit")
            ],
            path: "Sources/InterlinedDomain",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "InterlinedDomainTests",
            dependencies: ["InterlinedDomain"],
            path: "Tests/InterlinedDomainTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
