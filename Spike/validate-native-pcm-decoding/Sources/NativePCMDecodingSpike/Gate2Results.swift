import Foundation

// Result records for gate 2 (C, D, E). Same discipline as gate 1: every field is optional, an empty
// field prints as `—` and means **not observed**, and nothing is filled in by inference.

// MARK: - C — PCM layout

struct LayoutObservation {
    let fixture: String

    var fileFormatInterleaved: Bool?
    var processingFormatInterleaved: Bool?
    var numberBuffers: UInt32?
    var channelsPerBuffer: [UInt32]?
    var dataByteSizePerBuffer: [UInt32]?
    var floatChannelDataAvailable: Bool?

    var frameCapacity: UInt32?
    var chunkCount: Int?
    var firstChunkFrames: Int64?
    var lastChunkFrames: Int64?

    /// Sentinel pass: the whole buffer is overwritten with a sentinel before every read. After each
    /// read, the region `[frameLength, frameCapacity)` is inspected. `true` means the decoder wrote
    /// something there — which would make `frameLength` an unreliable bound.
    var decoderWroteBeyondFrameLength: Bool?

    /// No-wipe pass: after the short final read, the region `[frameLength, frameCapacity)` is
    /// compared with what it held **before** that read. `true` means stale samples from the previous
    /// chunk are still there — valid-looking data that a consumer must not read.
    var tailRetainsPreviousChunk: Bool?

    var error: String?
}

// MARK: - D — multichannel

struct MultichannelObservation {
    var generatedWithoutLayout: Bool?
    var generationErrorWithoutLayout: String?
    var generatedWithLayout: Bool?
    var generationErrorWithLayout: String?
    var layoutUsed: String?

    var framesWritten: Int64?
    var opened = false
    var openError: String?
    var fileFormat: String?
    var processingFormat: String?
    var declaredLength: Int64?
    var channels: UInt32?

    var framesRead: Int64?
    var chunkCount: Int?
    var readError: String?

    /// Per channel, in channel order: the value expected, and what was actually observed.
    var expectedPerChannel: [Float]?
    var minPerChannel: [Float]?
    var maxPerChannel: [Float]?
    var meanPerChannel: [Double]?
    var maxAbsErrorPerChannel: [Float]?

    /// Set only when it can be decided from the numbers above.
    var anyChannelPairIdentical: Bool?
}

// MARK: - E — values inside and outside the nominal range

struct RangeObservation {
    var generated: Bool?
    var generationError: String?
    var framesWritten: Int64?

    var opened = false
    var openError: String?
    var fileFormat: String?
    var processingFormat: String?
    var declaredLength: Int64?

    var framesRead: Int64?
    var readError: String?

    var writtenPerChannel: [[Float]]?
    var readPerChannel: [[Float]]?
    var minPerChannel: [Float]?
    var maxPerChannel: [Float]?
    var maxAbsErrorPerChannel: [Float]?

    /// `preserved` / `clipped at ±1` / `scaled` / a description of whatever else was seen. Never
    /// guessed: it is derived from the compared samples, and left `nil` when they are missing.
    var verdict: String?

    /// Set when the fixture could not be produced at all. The case is then **not tested**, and no
    /// alternative route is attempted.
    var notTestedReason: String?
}

// MARK: - Rendering

enum Gate2Report {
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

    static func show(_ value: Bool?) -> String {
        value.map(String.init(describing:)) ?? "—"
    }

    static func show(_ values: [UInt32]?) -> String {
        values.map { $0.map(String.init).joined(separator: ", ") } ?? "—"
    }

    static func show(_ values: [Float]?, precision: Int = 6) -> String {
        values.map { $0.map { String(format: "%.\(precision)f", $0) }.joined(separator: ", ") } ?? "—"
    }

    static func show(_ values: [Double]?, precision: Int = 6) -> String {
        values.map { $0.map { String(format: "%.\(precision)f", $0) }.joined(separator: ", ") } ?? "—"
    }

    static func layout(_ observations: [LayoutObservation]) {
        print("C — PCM LAYOUT")
        print("")
        for o in observations {
            print("── \(o.fixture) " + String(repeating: "─", count: max(0, 56 - o.fixture.count)))
            print("    fileFormat layout ............. \(o.fileFormatInterleaved.map { $0 ? "interleaved" : "planar" } ?? "—")")
            print("    processingFormat layout ....... \(o.processingFormatInterleaved.map { $0 ? "interleaved" : "planar" } ?? "—")")
            print("    AudioBufferList mNumberBuffers  \(show(o.numberBuffers))")
            print("    channels per buffer ........... \(show(o.channelsPerBuffer))")
            print("    byte size per buffer .......... \(show(o.dataByteSizePerBuffer))")
            print("    floatChannelData available .... \(show(o.floatChannelDataAvailable))")
            print("    frameCapacity ................. \(show(o.frameCapacity))")
            print("    chunks ........................ \(show(o.chunkCount))")
            print("    first chunk frameLength ....... \(show(o.firstChunkFrames))")
            print("    last chunk frameLength ........ \(show(o.lastChunkFrames))")
            print("    decoder wrote beyond length ... \(show(o.decoderWroteBeyondFrameLength))")
            print("    tail retains previous chunk ... \(show(o.tailRetainsPreviousChunk))")
            print("    error ......................... \(show(o.error))")
            print("")
        }
    }

    static func multichannel(_ o: MultichannelObservation) {
        print("D — MULTICHANNEL")
        print("")
        print("    generated without layout ...... \(show(o.generatedWithoutLayout))")
        print("    error without layout .......... \(show(o.generationErrorWithoutLayout))")
        print("    generated with layout ......... \(show(o.generatedWithLayout))")
        print("    error with layout ............. \(show(o.generationErrorWithLayout))")
        print("    layout used ................... \(show(o.layoutUsed))")
        print("    frames written ................ \(show(o.framesWritten))")
        print("    opened ........................ \(o.opened)")
        print("    open error .................... \(show(o.openError))")
        print("    fileFormat .................... \(show(o.fileFormat))")
        print("    processingFormat .............. \(show(o.processingFormat))")
        print("    channels ...................... \(show(o.channels))")
        print("    length (declared) ............. \(show(o.declaredLength))")
        print("    frames read ................... \(show(o.framesRead))")
        print("    chunks ........................ \(show(o.chunkCount))")
        print("    read error .................... \(show(o.readError))")
        print("    expected per channel .......... \(show(o.expectedPerChannel))")
        print("    min per channel ............... \(show(o.minPerChannel))")
        print("    max per channel ............... \(show(o.maxPerChannel))")
        print("    mean per channel .............. \(show(o.meanPerChannel))")
        print("    max abs error per channel ..... \(show(o.maxAbsErrorPerChannel, precision: 8))")
        print("    any two channels identical .... \(show(o.anyChannelPairIdentical))")
        print("")
    }

    static func range(_ o: RangeObservation) {
        print("E — VALUES INSIDE AND OUTSIDE ±1  (native float PCM only)")
        print("")
        if let reason = o.notTestedReason {
            print("    NOT TESTED: \(reason)")
            print("")
            return
        }
        print("    generated ..................... \(show(o.generated))")
        print("    generation error .............. \(show(o.generationError))")
        print("    frames written ................ \(show(o.framesWritten))")
        print("    opened ........................ \(o.opened)")
        print("    open error .................... \(show(o.openError))")
        print("    fileFormat .................... \(show(o.fileFormat))")
        print("    processingFormat .............. \(show(o.processingFormat))")
        print("    length (declared) ............. \(show(o.declaredLength))")
        print("    frames read ................... \(show(o.framesRead))")
        print("    read error .................... \(show(o.readError))")
        print("    min per channel ............... \(show(o.minPerChannel))")
        print("    max per channel ............... \(show(o.maxPerChannel))")
        print("    max abs error per channel ..... \(show(o.maxAbsErrorPerChannel, precision: 8))")
        print("    verdict ....................... \(show(o.verdict))")
        if let written = o.writtenPerChannel, let read = o.readPerChannel {
            for channel in written.indices where channel < read.count {
                let cycle = FixtureFactory.rangePattern.count
                let w = Array(written[channel].prefix(cycle))
                let r = Array(read[channel].prefix(cycle))
                print("    ch\(channel) written (first cycle) . \(show(w, precision: 4))")
                print("    ch\(channel) read    (first cycle) . \(show(r, precision: 4))")
            }
        }
        print("")
    }
}
