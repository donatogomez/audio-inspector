import Foundation

// Group 0 of `add-static-spectrogram-visualization`: does the proposed configuration actually let a
// collector see where a file's content stops?
//
// Run it with:
//
//     cd Spike/validate-static-spectrogram
//     swift build -c release -Xswiftc -warnings-as-errors
//     swift run  -c release StaticSpectrogramSpike
//
// It writes nothing inside the repository: real-file fixtures go to a fresh temporary directory that
// is removed on exit. The maths gates need no external tool; only the real-file gate uses FFmpeg, and
// it says so loudly when FFmpeg is missing.

print("STATIC SPECTROGRAM SPIKE — group 0 of add-static-spectrogram-visualization")
print("Every figure below is produced by this run. Nothing is quoted from a previous one.")

let fixtures = FileManager.default.temporaryDirectory
    .appendingPathComponent("static-spectrogram-spike-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtures) }

gateMath()
gateCutoff()
gateReduction()
gateChannels()
await gateEdges()
await gatePerformance()
gateRealFiles(in: fixtures)

ledger.summary()
print("\nfixtures directory removed: \(fixtures.lastPathComponent)")
