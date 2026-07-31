// swift-tools-version: 6.2
//
// AudioPropertySpike — a THROWAWAY exploratory spike for OpenSpec task 3.1 of
// `add-basic-audio-file-inspection`. It is a **sibling** SwiftPM package, deliberately kept OUTSIDE
// the productive `AudioInspectorKit` package and its `Sources/` tree, so:
//   - it is never linked from the app;
//   - it does not implement `AudioFilePropertyReading` or any domain type;
//   - `Scripts/check-boundaries.sh` (which scans the top-level `Sources/`) never sees it, so its
//     AVFoundation/CoreMedia imports cannot leak into the productive boundary rules.
//
// It matches the real deployment target (macOS 15) and builds in Swift 6 mode. Purpose: observe the
// RAW signals Apple's public APIs expose for local audio files. See
// docs/spikes/0031-audio-property-api-validation.md. Safe to delete after the findings are recorded.

import PackageDescription

let package = Package(
    name: "AudioPropertySpike",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "AudioPropertySpike",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
