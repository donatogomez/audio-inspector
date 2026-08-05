import AVFoundation
import Foundation

/// Gate G — real files through a real read path.
///
/// **Gated on FFmpeg, and the skip is loud.** macOS cannot encode MP3, so the fixtures come from
/// FFmpeg, which is a dev/test-only tool (ADR-0003). If it is absent this gate is SKIPPED and recorded
/// as such: a skipped gate is **not** evidence, and nothing may cite it as one. A failure inside the
/// gate stays a failure — it is never downgraded to a skip.
///
/// Fixtures are written to a caller-supplied temporary directory and removed with it. No audio binary
/// enters the repository, and running this spike writes nothing inside the working tree.
enum FFmpeg {
    static let executable: URL? = {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
        return candidates
            .map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }()

    static var isAvailable: Bool { executable != nil }

    struct Failure: Error, CustomStringConvertible {
        let arguments: [String]
        let status: Int32
        let output: String
        var description: String { "ffmpeg \(arguments.joined(separator: " ")) exited \(status):\n\(output)" }
    }

    /// A separated argument vector — never a shell string, so nothing in a path can be interpreted.
    @discardableResult
    static func run(_ arguments: [String]) throws -> String {
        guard let executable else { throw Failure(arguments: arguments, status: -1, output: "ffmpeg not installed") }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw Failure(arguments: arguments, status: process.terminationStatus, output: output)
        }
        return output
    }

    static func versionLine() throws -> String {
        try run(["-hide_banner", "-nostdin", "-version"]).split(separator: "\n").first.map(String.init) ?? "unknown"
    }
}

/// Reads a real file through `AVAudioFile` and folds it into the model, one chunk at a time.
///
/// Consumes exactly `buffer.frameLength` and never `frameCapacity` — the invariant ADR-0015 exists for.
func spectrogramOfFile(_ url: URL, chunkFrames: AVAudioFrameCount = 4_096, reduction: Reduction = .maximum) -> SpectrogramModel? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let format = file.processingFormat
    guard format.isStandard, !format.isInterleaved,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }

    let channelCount = Int(format.channelCount)
    let totalFrames = Int(file.length)
    guard let accumulator = SpectrogramAccumulator(
        sampleRate: format.sampleRate, channelCount: channelCount,
        totalFrames: totalFrames, reduction: reduction
    ) else { return nil }

    var consumed = 0
    while file.framePosition < file.length, consumed < totalFrames {
        guard (try? file.read(into: buffer)) != nil else { return nil }
        let valid = Int(buffer.frameLength)
        if valid == 0 { break }
        guard let data = buffer.floatChannelData else { return nil }
        let usable = min(valid, totalFrames - consumed)
        var chunk = [[Float]]()
        for channel in 0 ..< channelCount {
            chunk.append(Array(UnsafeBufferPointer(start: data[channel], count: usable)))
        }
        accumulator.accumulate(chunk)
        consumed += usable
    }
    return accumulator.finish()
}

@MainActor
func gateRealFiles(in directory: URL) {
    heading("GATE H — real files: WAV, FLAC, MP3 and WAV transcoded from MP3")

    guard FFmpeg.isAvailable else {
        ledger.skip("real-file comparison", reason: "FFmpeg is not installed on this machine. A skipped gate is NOT evidence: nothing may cite it as showing that containers behave alike.")
        return
    }

    do {
        line("  ffmpeg: \(try FFmpeg.versionLine())")
        let source = directory.appendingPathComponent("source.wav")
        let flac = directory.appendingPathComponent("lossless.flac")
        let mp3 = directory.appendingPathComponent("encoded.mp3")
        let transcoded = directory.appendingPathComponent("transcoded.wav")

        // A deterministic synthetic source: pink noise has energy everywhere, so a cutoff is obvious.
        try FFmpeg.run(["-hide_banner", "-nostdin", "-y", "-f", "lavfi",
                        "-i", "anoisesrc=r=44100:c=pink:d=8:a=0.4", "-ac", "2",
                        "-c:a", "pcm_s16le", source.path])
        try FFmpeg.run(["-hide_banner", "-nostdin", "-y", "-i", source.path, "-c:a", "flac", flac.path])
        try FFmpeg.run(["-hide_banner", "-nostdin", "-y", "-i", source.path, "-map_metadata", "-1",
                        "-c:a", "libmp3lame", "-b:a", "128k", mp3.path])
        try FFmpeg.run(["-hide_banner", "-nostdin", "-y", "-i", mp3.path, "-c:a", "pcm_s16le", transcoded.path])

        let files = [("source.wav", source), ("lossless.flac", flac), ("encoded.mp3", mp3), ("transcoded.wav", transcoded)]
        var models: [(name: String, model: SpectrogramModel)] = []
        for (name, url) in files {
            guard let model = spectrogramOfFile(url) else {
                ledger.check("\(name) decodes", false, detail: "could not be read")
                continue
            }
            models.append((name, model))
        }

        line("\n  file             | sample rate | columns | highest band above -90 dBFS")
        line("  -----------------|-------------|---------|----------------------------")
        for (name, model) in models {
            let edge = model.highestFrequency(above: -90).map { String(format: "%8.0f Hz", $0) } ?? "      none"
            line("  \(name.padding(toLength: 16, withPad: " ", startingAt: 0)) | \(String(format: "%7.0f", model.sampleRate)) Hz  | \(String(format: "%7d", model.columns)) | \(edge)")
        }

        line("\n  peak dBFS per frequency, across the whole file")
        var header = "   kHz   "
        for (name, _) in models {
            header += "| " + name.replacingOccurrences(of: ".wav", with: "")
                .replacingOccurrences(of: ".flac", with: "")
                .replacingOccurrences(of: ".mp3", with: "")
                .padding(toLength: 12, withPad: " ", startingAt: 0)
        }
        line(header)
        for frequency in [10_000.0, 14_000, 15_000, 16_000, 16_500, 17_000, 18_000, 19_000, 20_000, 21_000] {
            var row = String(format: "  %5.1f  ", frequency / 1_000)
            for (_, model) in models {
                if let peak = model.peak(atFrequency: frequency) {
                    row += String(format: "| %8.1f dB", peak)
                } else {
                    row += "|      —      "
                }
            }
            line(row)
        }

        func model(_ name: String) -> SpectrogramModel? { models.first { $0.name == name }?.model }

        if let wav = model("source.wav"), let lossless = model("lossless.flac") {
            ledger.check("WAV and FLAC of the same audio are identical", wav.values == lossless.values,
                         detail: "the container does not change what the spectrogram observes")
        }

        if let encoded = model("encoded.mp3"), let round = model("transcoded.wav"),
           let encodedEdge = encoded.highestFrequency(above: -90), let roundEdge = round.highestFrequency(above: -90) {
            ledger.check("the cutoff survives being rewrapped as WAV", abs(encodedEdge - roundEdge) < 200,
                         detail: "MP3 \(String(format: "%.0f", encodedEdge)) Hz vs WAV-from-MP3 \(String(format: "%.0f", roundEdge)) Hz")
        }

        if let wav = model("source.wav"), let encoded = model("encoded.mp3"),
           let wavEdge = wav.highestFrequency(above: -90), let encodedEdge = encoded.highestFrequency(above: -90) {
            ledger.check("the lossy file's content stops well below the lossless one's", wavEdge - encodedEdge > 3_000,
                         detail: "\(String(format: "%.0f", wavEdge)) Hz vs \(String(format: "%.0f", encodedEdge)) Hz")
        }

        line("\n  What this shows, and what it does not:")
        line("    SHOWS  — where energy stops, and that the container does not change that observation.")
        line("    DOES NOT SHOW — why it stops. A cutoff is compatible with lossy encoding, with the")
        line("    master, or with deliberate filtering, and this evidence does not separate them.")

        line("\n  real file, independence from the read chunk size")
        if let reference = spectrogramOfFile(source, chunkFrames: 65_536) {
            for chunk in [AVAudioFrameCount(1), 512, 4_096] {
                guard let model = spectrogramOfFile(source, chunkFrames: chunk) else { continue }
                ledger.check("reading source.wav in chunks of \(chunk) frames gives an identical model",
                             model.values == reference.values)
            }
        }
    } catch {
        // A failure here is a failure. It is never downgraded to a skip.
        ledger.check("the real-file gate ran to completion", false, detail: "\(error)")
    }
}
