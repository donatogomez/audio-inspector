import AVFoundation
import Foundation

/// Exploratory spike entry point (OpenSpec task 3.1). Two modes:
///  - with file-path arguments → diagnostic dump of each file;
///  - with no arguments → the full A–I experiment suite over self-generated PCM fixtures in a temp dir.
@main
struct AudioPropertySpike {
    static func main() async {
        print("AudioPropertySpike — native audio property API validation (task 3.1)")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        let paths = Array(CommandLine.arguments.dropFirst())
        if !paths.isEmpty {
            for path in paths {
                await inspect(URL(fileURLWithPath: path), label: "arg")
            }
            return
        }

        // A genuine setup failure (temp dir / fixture generation) must exit non-zero. The suite returns
        // only after its `defer` cleanup has run, so calling exit() here never skips cleanup.
        let ok = await runExperimentSuite()
        if !ok { exit(EXIT_FAILURE) }
    }

    /// Runs the full A–I suite. Returns `false` on a fatal setup failure (after cleaning up).
    static func runExperimentSuite() async -> Bool {
        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory.appendingPathComponent("audio-property-spike-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            print("FATAL: could not create work dir: \(error)")
            return false
        }
        defer { try? fileManager.removeItem(at: workDir) }

        // Fixture A — WAV PCM, mono, 22050 Hz, 16-bit, 0.5 s.
        // Fixture B — AIFF PCM, stereo, 44100 Hz, 16-bit, 0.25 s.
        let wavURL = workDir.appendingPathComponent("fixtureA.wav")
        let aiffURL = workDir.appendingPathComponent("fixtureB.aiff")
        do {
            try generatePCMFixture(at: wavURL, sampleRate: 22050, channels: 1, bitDepth: 16, bigEndian: false, seconds: 0.5)
            try generatePCMFixture(at: aiffURL, sampleRate: 44100, channels: 2, bitDepth: 16, bigEndian: true, seconds: 0.25)
        } catch {
            print("FATAL: fixture generation failed: \(error)")
            return false // `defer` above still runs → temp dir cleaned up before the caller exits non-zero
        }

        header("EXPERIMENT C (helper) — codec token serialization (synthetic, exercises the hex fallback)")
        for code in [0x6C70_636D, 0x6161_6320, 0x6D73_0000, 0x0000_0001] as [UInt32] {
            // 'lpcm' (printable) · 'aac ' (trailing space) · 'ms\0\0' (nulls) · pure control/binary
            print("  fourCCToken(0x\(String(format: "%08X", code))) = \(fourCCToken(code))")
        }

        header("EXPERIMENTS A–E, G — well-formed fixtures (raw signals)")
        print("Fixture A expected: WAV/PCM mono 22050 Hz 16-bit 0.5 s")
        await inspect(wavURL, label: "A/wav")
        print("Fixture B expected: AIFF/PCM stereo 44100 Hz 16-bit 0.25 s")
        await inspect(aiffURL, label: "B/aiff")

        header("EXPERIMENT F — container vs extension (misleading extension, bytes unchanged)")
        let lyingAiff = workDir.appendingPathComponent("actuallyWav.aiff")
        let lyingBin = workDir.appendingPathComponent("actuallyWav.bin")
        do {
            try fileManager.copyItem(at: wavURL, to: lyingAiff) // WAV bytes, .aiff name
            try fileManager.copyItem(at: wavURL, to: lyingBin)  // WAV bytes, .bin name
            print("Both files contain the WAV bytes of Fixture A, only the extension differs.")
            await inspect(lyingAiff, label: "F/.aiff-liar")
            await inspect(lyingBin, label: "F/.bin-liar")
        } catch {
            print("Experiment F setup error: \(error)")
        }

        header("EXPERIMENT H — error / edge cases")
        // H1 nonexistent path
        await inspect(workDir.appendingPathComponent("does-not-exist.wav"), label: "H1/missing")
        // H2 empty file with audio extension
        let emptyURL = workDir.appendingPathComponent("empty.wav")
        fileManager.createFile(atPath: emptyURL.path, contents: Data())
        await inspect(emptyURL, label: "H2/empty")
        // H3 text file with audio extension
        let textURL = workDir.appendingPathComponent("nottaudio.wav")
        fileManager.createFile(atPath: textURL.path, contents: Data("this is plain text, not audio\n".utf8))
        await inspect(textURL, label: "H3/text-as-wav")
        // H4 truncated copy of Fixture A (first 200 bytes)
        let truncatedURL = workDir.appendingPathComponent("truncatedA.wav")
        if let full = try? Data(contentsOf: wavURL) {
            let truncated = full.prefix(200)
            try? truncated.write(to: truncatedURL)
            print("Truncated file = first \(truncated.count) bytes of Fixture A.")
            await inspect(truncatedURL, label: "H4/truncated")
        }

        header("DONE — work dir will be removed")
        print("(All fixtures and temp copies were generated at runtime and are now deleted.)")
        return true
    }

    static func header(_ title: String) {
        print("")
        print("======================================================================")
        print("== \(title)")
        print("======================================================================")
    }
}
