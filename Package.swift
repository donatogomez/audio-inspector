// swift-tools-version: 6.2
//
// AudioInspectorKit — the modular Swift package behind Audio Inspector.
//
// The layering rules in docs/architecture.md and ADR-0005 are enforced here as build constraints:
// a target can only see the targets it explicitly declares, so e.g. a Feature target literally
// cannot `import AudioInspectorMedia`. Scripts/check-boundaries.sh backstops this on full builds.
//
// Every target builds in Swift 6 language mode → complete strict-concurrency checking.
// No external dependencies, no CLI/executable targets (see ADR-0001).

import PackageDescription

let swift6: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "AudioInspectorKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // The composition root, linked by the Xcode macOS app target.
        .library(name: "AudioInspectorApp", targets: ["AudioInspectorApp"]),
    ],
    targets: [
        // MARK: - Domain (pure business core — depends on NOTHING)

        .target(name: "AudioInspectorDomain", swiftSettings: swift6),

        // MARK: - Analysis (pure DSP — Domain only; Accelerate added when DSP lands)

        .target(
            name: "AudioInspectorAnalysis",
            dependencies: ["AudioInspectorDomain"],
            swiftSettings: swift6
        ),

        // MARK: - Media (probing/decoding adapters — Domain only; AVFoundation/AudioToolbox added when used)

        .target(
            name: "AudioInspectorMedia",
            dependencies: ["AudioInspectorDomain"],
            swiftSettings: swift6
        ),

        // MARK: - Testing support (fixtures/fakes — reused by tests and previews)

        .target(
            name: "AudioInspectorTesting",
            dependencies: ["AudioInspectorDomain", "AudioInspectorAnalysis"],
            swiftSettings: swift6
        ),

        // MARK: - Features (vertical UI slices — Domain only, never Media/Analysis)

        .target(
            name: "FeatureImport",
            dependencies: ["AudioInspectorDomain"],
            swiftSettings: swift6
        ),
        .target(
            name: "FeatureAnalysis",
            dependencies: ["AudioInspectorDomain"],
            swiftSettings: swift6
        ),

        // MARK: - App (composition root — the ONLY target that sees the concretes)

        .target(
            name: "AudioInspectorApp",
            dependencies: [
                "AudioInspectorDomain",
                "AudioInspectorAnalysis",
                "AudioInspectorMedia",
                "FeatureImport",
                "FeatureAnalysis",
            ],
            swiftSettings: swift6
        ),

        // MARK: - Tests (one link/compile smoke test per target)

        .testTarget(
            name: "AudioInspectorKitTests",
            dependencies: [
                "AudioInspectorDomain",
                "AudioInspectorAnalysis",
                "AudioInspectorMedia",
                "AudioInspectorTesting",
                "FeatureImport",
                "FeatureAnalysis",
                "AudioInspectorApp",
            ],
            swiftSettings: swift6
        ),
    ]
)
