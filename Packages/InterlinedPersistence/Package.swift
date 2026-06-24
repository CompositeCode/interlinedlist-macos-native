// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InterlinedPersistence",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "InterlinedPersistence",
            targets: ["InterlinedPersistence"]
        )
    ],
    dependencies: [
        .package(path: "../InterlinedDomain"),
        .package(path: "../InterlinedKit")
    ],
    targets: [
        .target(
            name: "InterlinedPersistence",
            dependencies: [
                .product(name: "InterlinedDomain", package: "InterlinedDomain"),
                .product(name: "InterlinedKit", package: "InterlinedKit")
            ],
            path: "Sources/InterlinedPersistence",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "InterlinedPersistenceTests",
            dependencies: [
                "InterlinedPersistence",
                .product(name: "InterlinedKit", package: "InterlinedKit")
            ],
            path: "Tests/InterlinedPersistenceTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
