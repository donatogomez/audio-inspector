// swift-tools-version: 6.2
//
// validate-native-pcm-decoding — a THROWAWAY exploratory spike. It exists to resolve the decoding
// hypothesis ADR-0003 left open ("native sufficiency is a hypothesis, not yet verified") before any
// sample-reading code enters the product. It is deliberately NOT an OpenSpec change: OpenSpec
// requires requirement deltas, and the evidence needed to write those deltas honestly is exactly
// what this spike is meant to produce.
//
// Like `Spike/AudioPropertySpike` (see docs/spikes/0031-audio-property-api-validation.md), it is a
// **sibling** SwiftPM package kept OUTSIDE the productive `AudioInspectorKit` package and its
// `Sources/` tree, so:
//   - it is never linked from the app and is not part of `swift build` / `swift test` at the root;
//   - it declares no domain port, no domain type, and no productive adapter;
//   - `Scripts/check-boundaries.sh` (which scans the top-level `Sources/`) never sees it, so its
//     AVFoundation imports cannot leak into the productive boundary rules.
//
// It matches the real deployment target (macOS 15) and builds in Swift 6 language mode with strict
// concurrency, because two of the questions under investigation — one `AVAudioFile` instance per
// task, and the cost of moving PCM chunks across an isolation boundary — are only meaningful under
// the same rules the product compiles with.
//
// Report: docs/spikes/2026-08-05-native-pcm-decoding-validation.md
// Safe to delete once the findings are recorded and ADR-0015 is written.

import PackageDescription

let package = Package(
    name: "validate-native-pcm-decoding",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "NativePCMDecodingSpike",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
