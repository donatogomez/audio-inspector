// swift-tools-version: 6.2
//
// Throwaway spike for group 2 of `add-true-peak-measurement`.
//
// **Deliberately outside the production graph.** Its own package, not a target of `AudioInspectorKit`,
// and the root `Package.swift` is untouched — so nothing here can be linked by accident and
// `swift build` at the repository root never sees it. It exists to be run, read, and deleted once the
// slice's own tests cover its observations (the deletion criterion is written into the spike report).
//
// It depends on nothing but the platform: Accelerate for the transforms. **No AVFoundation**: every
// fixture is synthesised from a formula and written as a canonical RIFF/WAVE IEEE-float file by hand,
// so the evidence is reproducible from this source alone and never depends on a framework's own
// resampling or file writing.
//
// Builds in Swift 6 language mode with `-warnings-as-errors`, like the production package.

import PackageDescription

let package = Package(
    name: "TruePeakSpike",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "TruePeakSpike",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
