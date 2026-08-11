import Foundation

/// FFmpeg's `ebur128` as an independent implementation of the same standard (ADR-0003 §3: a dev/test
/// reference oracle, never shipped).
///
/// ## What it can and cannot answer
///
/// - The **summary** line prints the true peak at **one decimal place in dB** — too coarse to derive a
///   tolerance from.
/// - The **metadata** stream (`metadata=1` + `ametadata=mode=print`) prints
///   `lavfi.r128.true_peak` and `lavfi.r128.true_peaks_ch<N>` as **linear** values with **three decimal
///   places**, and per channel. That is the best granularity this build exposes, and it puts a hard
///   floor of ±0.0005 linear under any agreement claim — which must be budgeted separately from the
///   algorithm's own error rather than blended into one number.
/// - Its values are **running maxima**, emitted per 100 ms frame; the last one printed is the file's.
/// - `peak=true+sample` also yields `sample_peak`, so both halves of the clipping-independence
///   comparison come from the same run of the same tool.
enum Oracle {
    struct Reading {
        let truePeak: Double
        let truePeakPerChannel: [Double]
        let samplePeak: Double
        let samplePeakPerChannel: [Double]
    }

    static func version() -> String {
        let output = run("/opt/homebrew/bin/ffmpeg", ["-hide_banner", "-version"])
        return output.split(separator: "\n").first.map(String.init) ?? "unknown"
    }

    static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") }

    /// The exact command this spike runs, recorded so the report can quote it verbatim.
    static func command(for path: String) -> String {
        "ffmpeg -hide_banner -nostats -i \(path) "
            + "-af ebur128=peak=true+sample:metadata=1,ametadata=mode=print:file=- -f null -"
    }

    static func measure(path: String) -> Reading? {
        let output = run("/opt/homebrew/bin/ffmpeg", [
            "-hide_banner", "-nostats", "-i", path,
            "-af", "ebur128=peak=true+sample:metadata=1,ametadata=mode=print:file=-",
            "-f", "null", "-",
        ])
        var truePeak: Double?
        var samplePeak: Double?
        var truePerChannel: [Int: Double] = [:]
        var samplePerChannel: [Int: Double] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Double(parts[1]) else { continue }
            let key = String(parts[0])
            if key == "lavfi.r128.true_peak" { truePeak = max(truePeak ?? 0, value) }
            if key == "lavfi.r128.sample_peak" { samplePeak = max(samplePeak ?? 0, value) }
            if key.hasPrefix("lavfi.r128.true_peaks_ch"),
               let channel = Int(key.dropFirst("lavfi.r128.true_peaks_ch".count)) {
                truePerChannel[channel] = max(truePerChannel[channel] ?? 0, value)
            }
            if key.hasPrefix("lavfi.r128.sample_peaks_ch"),
               let channel = Int(key.dropFirst("lavfi.r128.sample_peaks_ch".count)) {
                samplePerChannel[channel] = max(samplePerChannel[channel] ?? 0, value)
            }
        }
        guard let truePeak, let samplePeak else { return nil }
        return Reading(
            truePeak: truePeak,
            truePeakPerChannel: truePerChannel.sorted { $0.key < $1.key }.map(\.value),
            samplePeak: samplePeak,
            samplePeakPerChannel: samplePerChannel.sorted { $0.key < $1.key }.map(\.value)
        )
    }

    /// A separated argument vector, never `sh -c` — the project's own subprocess rule (ADR-0003 §5),
    /// obeyed here too even though this is a spike.
    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
