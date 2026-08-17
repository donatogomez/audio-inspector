import Foundation

// Reading integrated loudness out of FFmpeg's `ebur128`.
//
// The tool itself is located and launched by `FFmpegTool`, which already exists for the MP3 and true
// peak suites; nothing about process handling is repeated here. What this file adds is the little that
// is specific to loudness — which turns out to be entirely about **not reading the wrong number**.
//
// ## The two `Threshold:` lines
//
// `ebur128` prints a summary with two blocks:
//
// ```
//   Integrated loudness:
//     I:         -23.0 LUFS
//     Threshold: -34.2 LUFS      ← the relative gate, BS.1770-5 eq. (6): absolutely-gated level − 10 LU
//
//   Loudness range:
//     LRA:        13.0 LU
//     Threshold: -44.0 LUFS      ← a DIFFERENT gate: EBU Tech 3342's −20 LU, for a different quantity
// ```
//
// The two lines are textually identical apart from their value. Taking the second one is a silent
// 10 LU error that no assertion about integrated loudness would obviously catch, which is why the
// parser is section-aware and why `LoudnessOracleParsingTests` pins that behaviour with no tool
// present.
//
// ## Precision
//
// The summary prints **one** decimal, and the published compliance tolerance is ±0.1 — so a reading
// taken from the summary is compared at the same resolution as the bound it is being judged against.
// The `lavfi.r128.I` metadata stream prints **three**, so the integrated value is taken from there and
// the threshold, which needs no such resolution, from the summary. One invocation yields both.
enum LoudnessOracle {

    /// What the oracle reports for a file.
    struct Reading: Equatable {
        /// Integrated loudness in LUFS, at the metadata stream's three decimals.
        let integrated: Double
        /// The **relative gate** the meter derived — the threshold inside the *Integrated loudness*
        /// block. Never the *Loudness range* one.
        let relativeThreshold: Double
    }

    /// The output was produced but does not contain what it should. Kept separate from
    /// `FFmpegTool.Failure`, which means the tool itself failed, and from a missing tool, which means
    /// the suite skips: three different situations that must never be collapsed into one.
    enum ParseFailure: Error, CustomStringConvertible {
        case noIntegratedValue(output: String)
        case noIntegratedThreshold(output: String)

        var description: String {
            switch self {
            case .noIntegratedValue:
                "ebur128 emitted no lavfi.r128.I metadata — was metadata=1 set, and did the file decode?"
            case .noIntegratedThreshold:
                """
                ebur128 emitted no threshold inside its 'Integrated loudness:' block. The summary is \
                logged at INFO level, so -loglevel error discards it.
                """
            }
        }
    }

    /// Arguments for one measurement. A **separated vector**, never a shell string.
    static func arguments(for url: URL) -> [String] {
        [
            "-hide_banner", "-nostdin", "-nostats",
            "-i", url.path,
            "-af", "ebur128=metadata=1,ametadata=mode=print:file=-",
            "-f", "null", "-",
        ]
    }

    /// Measures `url`. Throws `FFmpegTool.Failure` if the tool is missing or exits non-zero, and
    /// `ParseFailure` if it ran but said nothing usable.
    static func read(_ url: URL) throws -> Reading {
        try parse(FFmpegTool.run(arguments(for: url)))
    }

    /// The pure half, so the rule about the two thresholds is testable without the tool.
    static func parse(_ output: String) throws -> Reading {
        var integrated: Double?
        var relativeThreshold: Double?
        var insideIntegratedBlock = false

        // stdout (the metadata stream) and stderr (the summary) share one pipe, so the summary can
        // appear part-way through the metadata rather than after it. Nothing below depends on their
        // relative order: the metadata is reduced by taking the last value, and the summary's own two
        // lines keep their order because they come from the same stream.
        for rawLine in output.split(separator: "\n") {
            let line = stripLogPrefix(rawLine.trimmingCharacters(in: .whitespaces))

            // The metadata stream. Match the key exactly: `lavfi.r128.LRA` and `lavfi.r128.LRA.low`
            // share a prefix with nothing here, but a prefix match would happily accept them.
            if let separator = line.firstIndex(of: "="),
               line[line.startIndex ..< separator] == "lavfi.r128.I",
               let value = Double(line[line.index(after: separator)...])
            {
                // The last one is the whole-file result; earlier ones are the running value.
                integrated = value
                continue
            }

            // The summary. `Threshold:` appears in both blocks, so track which one we are in.
            if line.hasPrefix("Integrated loudness:") {
                insideIntegratedBlock = true
                continue
            }
            if line.hasPrefix("Loudness range:") || line.hasPrefix("True peak:") {
                insideIntegratedBlock = false
                continue
            }
            if insideIntegratedBlock, line.hasPrefix("Threshold:"), relativeThreshold == nil {
                relativeThreshold = firstNumber(in: line)
            }
        }

        guard let integrated else { throw ParseFailure.noIntegratedValue(output: output) }
        guard let relativeThreshold else { throw ParseFailure.noIntegratedThreshold(output: output) }
        return Reading(integrated: integrated, relativeThreshold: relativeThreshold)
    }

    /// Removes FFmpeg's `[Parsed_ametadata_1 @ 0x…] ` log prefix.
    ///
    /// With `file=-` the metadata is written raw to stdout and carries no prefix, which is how this is
    /// invoked. Without it the same lines arrive through the log with one. Handling both means the
    /// invocation can change without the parser quietly returning nothing.
    private static func stripLogPrefix(_ line: String) -> String {
        guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return line }
        return String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func firstNumber(in line: String) -> Double? {
        line
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .lazy
            .compactMap { Double($0) }
            .first
    }
}
