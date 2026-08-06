import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorTesting
import Foundation
import Testing

// Two things the accumulator's own arithmetic cannot show: that folding a decode into it stays
// cancellable, and that Accelerate stops where the module does.
//
// **Task 4.8 is demonstrated by this file compiling.** It imports `AudioInspectorAnalysis` without
// `@testable` and without importing Accelerate, yet builds a `SpectrogramAccumulator`, feeds it and
// reads the model. Were `DSPSplitComplex`, `vDSP.*` or the transform setup present in any signature the
// module exposes, this file would not compile without importing Accelerate too.

@Suite("Analysis — spectrogram accumulation is cancellable")
struct SpectrogramAccumulationCancellationTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: nil, sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(frames: Int) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: frames))
    }

    private func chunks(frames: Int, per chunkFrames: Int) throws -> [PCMChunk] {
        try stride(from: 0, to: frames, by: chunkFrames).map { start in
            let count = min(chunkFrames, frames - start)
            let samples = (0 ..< count).map { offset -> Float in
                let phase = 2 * Double.pi * 1_000 * Double(start + offset) / 44_100
                return 0.5 * Float(sin(phase))
            }
            return try PCMChunk(startFrame: start, channels: [samples])
        }
    }

    /// The composition a caller will write: decode, fold, finish. Cancellation is observed at chunk
    /// boundaries by the consumer's own callback, and a cancelled run produces **no model at all** —
    /// never a partial one presented as whole.
    ///
    /// No sleep and no timing assumption: the task is cancelled before it is awaited, so the flag is
    /// already set when the first boundary is reached.
    @Test("a cancelled accumulation yields no model, not a partial one")
    func cancellationYieldsNoModel() async throws {
        let frames = 40_960
        let description = try stream(frames: frames)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: frames, per: 512))
        let file = reference()

        let task = Task { () -> Spectrogram? in
            var accumulator = SpectrogramAccumulator(
                sampleRate: description.sampleRate,
                channelCount: description.channelCount,
                frameCount: description.frameCount
            )
            var cancelled = false
            _ = try await decoder.decode(file, chunkFrames: 512) { chunk in
                if Task.isCancelled {
                    cancelled = true
                    return .stop
                }
                accumulator?.accumulate(chunk)
                return .continue
            }
            return cancelled ? nil : accumulator?.finish()
        }
        task.cancel()

        let model = try await task.value
        #expect(model == nil, "a cancelled accumulation produced a model")
    }

    /// The same composition, uncancelled, must produce the whole model — so the test above is observing
    /// cancellation rather than a composition that never worked.
    @Test("the same composition uncancelled produces the whole model")
    func theUncancelledCompositionSucceeds() async throws {
        let frames = 40_960
        let description = try stream(frames: frames)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: frames, per: 512))

        var accumulator = try #require(SpectrogramAccumulator(
            sampleRate: description.sampleRate,
            channelCount: description.channelCount,
            frameCount: description.frameCount
        ))
        _ = try await decoder.decode(reference(), chunkFrames: 512) { chunk in
            accumulator.accumulate(chunk)
            return .continue
        }

        let model = try #require(accumulator.finish())
        #expect(model.frameCount == frames)
        #expect(model.columnCount > 0)
        #expect(model.values.contains { $0 > -20 }, "the signal reached the model")
    }

    /// A consumer that stops early leaves the model describing only what it saw, and the accumulator
    /// still returns a well-formed one rather than refusing.
    @Test("stopping early leaves a model of what was actually read")
    func stoppingEarlyStillProducesAModel() async throws {
        let frames = 40_960
        let description = try stream(frames: frames)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: frames, per: 512))

        var accumulator = try #require(SpectrogramAccumulator(
            sampleRate: description.sampleRate,
            channelCount: description.channelCount,
            frameCount: description.frameCount
        ))
        var seen = 0
        _ = try await decoder.decode(reference(), chunkFrames: 512) { chunk in
            seen += 1
            accumulator.accumulate(chunk)
            return seen >= 8 ? .stop : .continue
        }

        let model = try #require(accumulator.finish())
        #expect(model.frameCount == frames, "the file's declared length is unchanged by stopping")
        // Only the columns covering what was read carry energy; the rest stay at the floor rather than
        // being fabricated.
        #expect(model.values.contains { $0 == Spectrogram.floorDecibels })
    }
}

@Suite("Analysis — module boundaries")
struct SpectrogramModuleBoundaryTests {
    /// `Scripts/check-boundaries.sh` is the canonical gate and runs in CI; this repeats the two rules
    /// this group could break, so a violation fails the suite as well as the script.
    private func imports(of directory: String) throws -> [(file: String, line: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let target = root.appendingPathComponent(directory)
        let files = FileManager.default.enumerator(at: target, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        return try files.flatMap { file -> [(String, String)] in
            try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") }
                .map { (file.lastPathComponent, $0.trimmingCharacters(in: .whitespaces)) }
        }
    }

    /// The rule as `check-boundaries.sh` states it: no UI framework, no media framework, no Accelerate
    /// and no SwiftData. `Foundation` is not on that list and the domain already uses it for `Date`.
    @Test("no framework reaches the domain")
    func theDomainStaysPure() throws {
        let forbidden = ["AVFoundation", "AudioToolbox", "CoreAudio", "Accelerate", "SwiftUI", "AppKit", "SwiftData"]
        let found = try imports(of: "Sources/AudioInspectorDomain")
            .filter { line in forbidden.contains { line.line.contains($0) } }
        #expect(found.isEmpty, "the domain imported: \(found)")
    }

    /// The spectrogram contract specifically: the seven types this change added to the domain import
    /// nothing whatsoever, framework or otherwise.
    @Test("the spectrogram's domain types import nothing whatsoever")
    func theSpectrogramContractImportsNothing() throws {
        let owned: Set<String> = [
            "AudioDecoding.swift", "AudioDecodingError.swift", "PCMChunk.swift",
            "PCMStreamDescription.swift", "Spectrogram.swift", "SpectrogramGridMapping.swift",
        ]
        let found = try imports(of: "Sources/AudioInspectorDomain").filter { owned.contains($0.file) }
        #expect(found.isEmpty, "a spectrogram domain type imported: \(found)")
    }

    /// Accelerate is Analysis's alone, and it may not reach any other module.
    @Test("Analysis imports only the domain and Accelerate")
    func analysisImportsOnlyWhatItOwns() throws {
        let allowed: Set<String> = ["import Accelerate", "import AudioInspectorDomain", "import Foundation"]
        let found = try imports(of: "Sources/AudioInspectorAnalysis")
        let unexpected = found.filter { !allowed.contains($0.line) }
        #expect(unexpected.isEmpty, "Analysis imported: \(unexpected)")
        #expect(found.contains { $0.line == "import Accelerate" }, "the transform should be here")
    }

    @Test("no module outside Analysis imports Accelerate")
    func accelerateStaysInAnalysis() throws {
        for module in [
            "Sources/AudioInspectorDomain", "Sources/AudioInspectorMedia",
            "Sources/AudioInspectorTesting", "Sources/FeatureAnalysis",
            "Sources/FeatureImport", "Sources/AudioInspectorApp",
        ] {
            let found = try imports(of: module).filter { $0.line.contains("Accelerate") }
            #expect(found.isEmpty, "\(module) imported Accelerate: \(found)")
        }
    }

    @Test("no media framework reaches Analysis")
    func noMediaFrameworkInAnalysis() throws {
        let found = try imports(of: "Sources/AudioInspectorAnalysis")
            .filter { $0.line.contains("AVFoundation") || $0.line.contains("AudioToolbox") }
        #expect(found.isEmpty, "Analysis imported a media framework: \(found)")
    }
}
