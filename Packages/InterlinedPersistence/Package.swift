// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InterlinedPersistence",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "InterlinedPersistence",
            targets: ["InterlinedPersistence"]
        )
    ],
    dependencies: [
        .package(path: "../InterlinedDomain")
    ],
    targets: [
        .target(
            name: "InterlinedPersistence",
            dependencies: [
                .product(name: "InterlinedDomain", package: "InterlinedDomain")
            ],
            path: "Sources/InterlinedPersistence",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "InterlinedPersistenceTests",
            dependencies: ["InterlinedPersistence"],
            path: "Tests/InterlinedPersistenceTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
