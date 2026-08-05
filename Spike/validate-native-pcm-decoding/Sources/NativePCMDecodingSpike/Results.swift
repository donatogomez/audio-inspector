import Foundation

/// One row of the matrix: everything observed about a single fixture format, field by field.
///
/// Every field is optional and starts empty. An empty field prints as `—` and means **not observed**;
/// it is never filled in from a neighbouring column, from another format, or from a plausible
/// default. Generation and reading are deliberately kept in separate groups: writing a format
/// successfully proves nothing about reading it, and reading proves nothing about writing.
struct FormatObservation {
    let fixture: String
    let fileExtension: String

    // MARK: Generation

    // Not an experiment — a precondition, recorded separately so a failure here is never mistaken
    // for a decoding failure.

    var generated = false
    var generationError: String?
    var framesWritten: Int64?
    var fileSizeBytes: Int64?

    // MARK: Experiment A — open, formats, frame length

    var opened = false
    var openError: String?
    var fileFormat: String?
    var processingFormat: String?
    var fileFormatInterleaved: Bool?
    var processingFormatInterleaved: Bool?
    var channels: UInt32?
    var sampleRate: Double?
    var declaredLength: Int64?

    // MARK: Experiment B — incremental read to EOF

    var readAttempted = false
    var readError: String?
    var framesRead: Int64?
    var chunkCount: Int?
    var firstChunkFrames: Int64?
    var lastChunkFrames: Int64?
    var eofSignal: String?
    var framePositionAtStop: Int64?

    // MARK: Experiment B, control — the `framePosition < length` idiom

    // Same read, on a freshly opened instance, stopping on the guard instead of on the decoder's own
    // signal. It exists to tell two explanations apart: "EOF is signalled by a throw" versus "the
    // unguarded loop has a defect". Without it, the throw observed above could not be attributed.

    var guardedAttempted = false
    var guardedFramesRead: Int64?
    var guardedChunkCount: Int?
    var guardedThrew: Bool?
    var guardedError: String?
    var guardedFinalFramePosition: Int64?

    /// Frames actually read minus frames declared by `length`. `nil` when either side is missing —
    /// a difference against an unknown is not zero, it is unknown.
    var lengthDelta: Int64? {
        guard let declaredLength, let framesRead else { return nil }
        return framesRead - declaredLength
    }
}

// MARK: - Rendering

enum Report {
    static func show(_ value: Int64?) -> String {
        value.map(String.init) ?? "—"
    }

    static func show(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    static func show(_ value: UInt32?) -> String {
        value.map(String.init) ?? "—"
    }

    static func show(_ value: String?) -> String {
        value ?? "—"
    }

    static func show(_ value: Double?) -> String {
        value.map { String(format: "%.0f", $0) } ?? "—"
    }

    static func show(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "interleaved" : "planar"
    }

    static func detail(_ observation: FormatObservation) {
        let o = observation
        print("── \(o.fixture) (.\(o.fileExtension)) " + String(repeating: "─", count: max(0, 52 - o.fixture.count)))
        print("  generation")
        print("    generated ............... \(o.generated)")
        print("    generation error ........ \(show(o.generationError))")
        print("    frames written .......... \(show(o.framesWritten))")
        print("    file size (bytes) ....... \(show(o.fileSizeBytes))")
        print("  A — open, formats, frame length")
        print("    opened .................. \(o.opened)")
        print("    open error .............. \(show(o.openError))")
        print("    fileFormat .............. \(show(o.fileFormat))")
        print("    fileFormat layout ....... \(show(o.fileFormatInterleaved))")
        print("    processingFormat ........ \(show(o.processingFormat))")
        print("    processingFormat layout . \(show(o.processingFormatInterleaved))")
        print("    channels ................ \(show(o.channels))")
        print("    sample rate (Hz) ........ \(show(o.sampleRate))")
        print("    length (declared frames)  \(show(o.declaredLength))")
        print("  B — incremental read to EOF")
        print("    read attempted .......... \(o.readAttempted)")
        print("    read error .............. \(show(o.readError))")
        print("    frames read ............. \(show(o.framesRead))")
        print("    chunks .................. \(show(o.chunkCount))")
        print("    first chunk frames ...... \(show(o.firstChunkFrames))")
        print("    last chunk frames ....... \(show(o.lastChunkFrames))")
        print("    EOF signal .............. \(show(o.eofSignal))")
        print("    framePosition at stop ... \(show(o.framePositionAtStop))")
        print("    read − declared ......... \(show(o.lengthDelta))")
        print("  B control — `framePosition < length` idiom, fresh instance")
        print("    attempted ............... \(o.guardedAttempted)")
        print("    frames read ............. \(show(o.guardedFramesRead))")
        print("    chunks .................. \(show(o.guardedChunkCount))")
        print("    threw ................... \(o.guardedThrew.map(String.init(describing:)) ?? "—")")
        print("    error ................... \(show(o.guardedError))")
        print("    final framePosition ..... \(show(o.guardedFinalFramePosition))")
        print("")
    }

    static func summary(_ observations: [FormatObservation]) {
        print("SUMMARY")
        print("")
        let header = ["fixture", "gen", "open", "ch", "rate", "declared", "read", "delta", "layout"]
        let widths = [10, 5, 5, 3, 6, 9, 9, 7, 11]
        print(zip(header, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " "))
        print(widths.map { String(repeating: "─", count: $0) }.joined(separator: " "))
        for o in observations {
            let cells = [
                o.fixture,
                o.generated ? "yes" : "NO",
                o.opened ? "yes" : "NO",
                show(o.channels),
                show(o.sampleRate),
                show(o.declaredLength),
                show(o.framesRead),
                show(o.lengthDelta),
                show(o.processingFormatInterleaved),
            ]
            print(zip(cells, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " "))
        }
        print("")
    }
}
