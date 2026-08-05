// swift-tools-version: 6.2
//
// Throwaway spike for group 0 of `add-static-spectrogram-visualization`.
//
// **Deliberately outside the production graph.** It is its own package, it is not a target of
// `AudioInspectorKit`, and the root `Package.swift` is not touched — so nothing here can be linked by
// accident and `swift build` at the repository root never sees it. It exists to be run once, read, and
// deleted when ADR-0016 is Accepted and the slice's own tests cover its observations.
//
// It depends on nothing but the platform: Accelerate for the transform, AVFoundation to read real
// files. No third-party package, and no FFmpeg dependency — FFmpeg only ever produces fixtures for the
// optional gate, and its absence skips that gate loudly rather than failing it.
//
// Builds in Swift 6 language mode with `-warnings-as-errors`, like the production package, because the
// isolation question this spike answers is only meaningful under those rules.

import PackageDescription

let package = Package(
    name: "StaticSpectrogramSpike",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "StaticSpectrogramSpike",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
