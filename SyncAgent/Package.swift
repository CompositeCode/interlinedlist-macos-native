// swift-tools-version: 6.0
import PackageDescription

// InterlinedListSync — a standalone menu-bar agent that keeps a local folder of
// Markdown files bidirectionally synchronized with InterlinedList documents so
// external editors (e.g. Obsidian) can be used. Clean-room reimplementation:
// no dependency on the main app's InterlinedKit/Domain/Persistence packages.
//
// Split into a `Core` library (all logic + UI) and a thin executable so the
// logic can be unit-tested without the `@main` entry point.
let package = Package(
    name: "InterlinedListSync",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "InterlinedListSync", targets: ["InterlinedListSync"])
    ],
    targets: [
        .target(
            name: "InterlinedListSyncCore",
            path: "Sources/InterlinedListSyncCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "InterlinedListSync",
            dependencies: ["InterlinedListSyncCore"],
            path: "Sources/InterlinedListSync",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "InterlinedListSyncCoreTests",
            dependencies: ["InterlinedListSyncCore"],
            path: "Tests/InterlinedListSyncCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
