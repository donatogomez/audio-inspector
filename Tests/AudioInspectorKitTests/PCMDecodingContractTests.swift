import AudioInspectorDomain
import Testing

// The decoding seam's value types, over plain numbers. No file, no framework, no fixture: everything
// these types promise is a property of their own arithmetic, and is proved here rather than inferred
// from an integration test that happens to pass.

@Suite("Domain — PCM stream description")
struct PCMStreamDescriptionTests {
    @Test("a description keeps the three facts an analysis needs to be sized")
    func keepsItsParts() throws {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: 441_000))
        #expect(stream.sampleRate == 44_100)
        #expect(stream.channelCount == 2)
        #expect(stream.frameCount == 441_000)
        #expect(stream.nyquist == 22_050)
    }

    /// A readable header with no audio behind it. A complete answer, and a different thing from a file
    /// whose length could not be established — which the port reports as `nil`.
    @Test("zero frames describes a real file, not a failure")
    func zeroFramesIsValid() throws {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 0))
        #expect(stream.frameCount == 0)
    }

    @Test("an impossible sample rate is refused", arguments: [0.0, -1, -44_100])
    func refusesImpossibleSampleRates(sampleRate: Double) {
        #expect(PCMStreamDescription(sampleRate: sampleRate, channelCount: 2, frameCount: 100) == nil)
    }

    @Test("a sample rate that is not a number is refused", arguments: [Double.nan, .infinity, -.infinity, .signalingNaN])
    func refusesNonFiniteSampleRates(sampleRate: Double) {
        #expect(PCMStreamDescription(sampleRate: sampleRate, channelCount: 2, frameCount: 100) == nil)
    }

    @Test("a stream with no channels is refused", arguments: [0, -1, -2])
    func refusesChannelCounts(channelCount: Int) {
        #expect(PCMStreamDescription(sampleRate: 44_100, channelCount: channelCount, frameCount: 100) == nil)
    }

    @Test("a negative frame count is refused", arguments: [-1, -441_000])
    func refusesNegativeFrameCounts(frameCount: Int) {
        #expect(PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: frameCount) == nil)
    }

    @Test("the whole of Nyquist is available, at every rate", arguments: [44_100.0, 48_000, 96_000, 192_000])
    func nyquistIsHalfTheSampleRate(sampleRate: Double) throws {
        let stream = try #require(PCMStreamDescription(sampleRate: sampleRate, channelCount: 2, frameCount: 1_000))
        #expect(stream.nyquist == sampleRate / 2)
    }

    @Test("descriptions compare by value")
    func comparesByValue() throws {
        let one = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: 100))
        let same = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: 100))
        let other = try #require(PCMStreamDescription(sampleRate: 48_000, channelCount: 2, frameCount: 100))
        #expect(one == same)
        #expect(one != other)
    }
}

@Suite("Domain — PCM chunk")
struct PCMChunkTests {
    @Test("a mono chunk carries one channel of samples")
    func mono() throws {
        let chunk = try PCMChunk(startFrame: 0, channels: [[0.1, -0.2, 0.3]])
        #expect(chunk.channelCount == 1)
        #expect(chunk.frameCount == 3)
        #expect(chunk.samples(ofChannel: 0) == [0.1, -0.2, 0.3])
        #expect(chunk.samples(ofChannel: 1) == nil)
    }

    @Test("a stereo chunk keeps its channels apart")
    func stereo() throws {
        let chunk = try PCMChunk(startFrame: 512, channels: [[0.1, 0.2], [-0.1, -0.2]])
        #expect(chunk.channelCount == 2)
        #expect(chunk.frameCount == 2)
        #expect(chunk.startFrame == 512)
        #expect(chunk.samples(ofChannel: 0) == [0.1, 0.2])
        #expect(chunk.samples(ofChannel: 1) == [-0.1, -0.2])
    }

    @Test("more than two channels are ordinary", arguments: [3, 4, 6, 8])
    func manyChannels(channelCount: Int) throws {
        let channels = (0 ..< channelCount).map { channel in [Float(channel) / 10, Float(channel) / 20] }
        let chunk = try PCMChunk(startFrame: 0, channels: channels)
        #expect(chunk.channelCount == channelCount)
        #expect(chunk.frameCount == 2)
        for channel in 0 ..< channelCount {
            #expect(chunk.samples(ofChannel: channel)?.first == Float(channel) / 10)
        }
    }

    /// The invariant that makes the type planar: a ragged chunk cannot exist, so no consumer has to
    /// guess which channel's length is authoritative.
    @Test("channels of differing lengths are refused")
    func refusesRaggedChannels() {
        let error = #expect(throws: AudioDecodingError.self) {
            try PCMChunk(startFrame: 0, channels: [[0.1, 0.2, 0.3], [0.1, 0.2]])
        }
        #expect(error?.code == .invalidChunk)
    }

    @Test("a chunk with no channels is refused")
    func refusesNoChannels() {
        let error = #expect(throws: AudioDecodingError.self) {
            try PCMChunk(startFrame: 0, channels: [])
        }
        #expect(error?.code == .invalidChunk)
    }

    @Test("a negative starting frame is refused", arguments: [-1, -512])
    func refusesNegativeStartFrame(startFrame: Int) {
        let error = #expect(throws: AudioDecodingError.self) {
            try PCMChunk(startFrame: startFrame, channels: [[0.1]])
        }
        #expect(error?.code == .invalidChunk)
    }

    /// The boundary the spike argued for. A `NaN` reaching a reduction does not announce itself: it
    /// collapses cells to the floor and the result reads as an absence of energy.
    @Test("a sample that is not a number is refused", arguments: [Float.nan, .signalingNaN])
    func refusesNotANumber(sample: Float) {
        let error = #expect(throws: AudioDecodingError.self) {
            try PCMChunk(startFrame: 0, channels: [[0.1, sample, 0.3]])
        }
        #expect(error?.code == .nonFiniteSample)
    }

    @Test("an infinite sample is refused", arguments: [Float.infinity, -.infinity])
    func refusesInfinities(sample: Float) {
        let error = #expect(throws: AudioDecodingError.self) {
            try PCMChunk(startFrame: 0, channels: [[0.1, 0.2], [sample, 0.3]])
        }
        #expect(error?.code == .nonFiniteSample)
    }

    /// Beyond full scale is not the same as invalid. Those values are real, and clamping them here
    /// would quietly understate a file that genuinely exceeds full scale.
    @Test("finite values beyond [-1, 1] are preserved", arguments: [Float(1.5), -1.5, 12.5, -40])
    func keepsValuesBeyondNominalRange(sample: Float) throws {
        let chunk = try PCMChunk(startFrame: 0, channels: [[sample]])
        #expect(chunk.samples(ofChannel: 0) == [sample])
    }

    /// A decoder may hand over an empty run at the end of a file rather than special-casing it.
    @Test("an empty chunk is valid when its channels agree")
    func emptyChunkIsValid() throws {
        let chunk = try PCMChunk(startFrame: 100, channels: [[], []])
        #expect(chunk.frameCount == 0)
        #expect(chunk.channelCount == 2)
    }

    /// The shape an interleaved buffer would have to take. It is representable only as a *single*
    /// channel of `n × frames`, which no consumer could mistake for planar audio.
    @Test("an interleaved run cannot masquerade as planar")
    func interleavedCannotPassAsPlanar() throws {
        // Two channels of three frames, interleaved: L R L R L R.
        let interleaved: [Float] = [0.1, -0.1, 0.2, -0.2, 0.3, -0.3]
        let chunk = try PCMChunk(startFrame: 0, channels: [interleaved])
        #expect(chunk.channelCount == 1, "it is one channel of six frames, not two of three")
        #expect(chunk.frameCount == 6)
    }

    @Test("a chunk knows whether it fits the stream it claims to come from")
    func fitsTheStream() throws {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: 1_000))
        #expect(try PCMChunk(startFrame: 0, channels: [[0.1], [0.2]]).fits(stream))
        #expect(try PCMChunk(startFrame: 999, channels: [[0.1], [0.2]]).fits(stream))
        #expect(!(try PCMChunk(startFrame: 1_000, channels: [[0.1], [0.2]]).fits(stream)))
        #expect(!(try PCMChunk(startFrame: 0, channels: [[0.1]]).fits(stream)), "wrong channel count")
    }

    /// The exact boundary, from both sides. A chunk ending on the stream's last frame fits; one frame
    /// more does not.
    @Test("the last frame of the stream is inside it, and the next one is not")
    func fitsAtTheExactBoundary() throws {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 1_000))
        let samples = [Float](repeating: 0.1, count: 100)
        #expect(try PCMChunk(startFrame: 900, channels: [samples]).fits(stream), "ends exactly at 1000")
        #expect(!(try PCMChunk(startFrame: 901, channels: [samples]).fits(stream)), "would end at 1001")
        #expect(try PCMChunk(startFrame: 1_000, channels: [[]]).fits(stream), "an empty run at the end")
    }

    /// `fits(_:)` answers a question about values it does not trust, and the initialiser accepts any
    /// non-negative `startFrame` — so the arithmetic must survive one near `Int.max`. Before this was
    /// hardened, the sum trapped and took the process with it on exactly the input the check was asked
    /// about.
    @Test(
        "a chunk whose end frame cannot be represented does not fit, and does not abort",
        arguments: [Int.max, .max - 1, .max / 2 + 1]
    )
    func fitsRefusesInsteadOfOverflowing(startFrame: Int) throws {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 1_000))
        let chunk = try PCMChunk(startFrame: startFrame, channels: [[0.1, 0.2, 0.3]])
        #expect(!chunk.fits(stream))
    }

    /// The one case that does not overflow but still cannot fit: a start at `Int.max` carrying nothing.
    @Test("an empty chunk starting at the largest representable frame still does not fit")
    func emptyChunkAtTheEndOfTheNumberLineDoesNotFit() throws {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 1_000))
        let chunk = try PCMChunk(startFrame: .max, channels: [[]])
        #expect(chunk.frameCount == 0, "no overflow is even possible here")
        #expect(!chunk.fits(stream))
    }

    @Test("a chunk longer than the whole stream does not fit")
    func aChunkLongerThanTheStreamDoesNotFit() throws {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 10))
        let chunk = try PCMChunk(startFrame: 0, channels: [[Float](repeating: 0.1, count: 11)])
        #expect(!chunk.fits(stream))
    }

    /// A stream with no audio admits only the empty chunk that starts where it ends.
    @Test("nothing but an empty run fits a stream with no frames")
    func nothingFitsAStreamWithNoFrames() throws {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 0))
        #expect(try PCMChunk(startFrame: 0, channels: [[]]).fits(stream))
        #expect(!(try PCMChunk(startFrame: 0, channels: [[0.1]]).fits(stream)))
    }

    @Test("chunks compare by value")
    func comparesByValue() throws {
        let one = try PCMChunk(startFrame: 0, channels: [[0.1, 0.2]])
        let same = try PCMChunk(startFrame: 0, channels: [[0.1, 0.2]])
        let other = try PCMChunk(startFrame: 1, channels: [[0.1, 0.2]])
        #expect(one == same)
        #expect(one != other)
    }
}

@Suite("Domain — PCM chunk disposition")
struct PCMChunkDispositionTests {
    /// Two cases and no more. Stopping early is not a failure, and a consumer's own error space already
    /// expresses one — so this channel deliberately cannot carry it.
    @Test("stopping is distinct from continuing, and neither is an error")
    func twoCasesOnly() {
        #expect(PCMChunkDisposition.continue != PCMChunkDisposition.stop)
        #expect(PCMChunkDisposition.continue == PCMChunkDisposition.continue)
        #expect(PCMChunkDisposition.stop == PCMChunkDisposition.stop)
    }
}

// MARK: - The port's own contract

/// A stub that exists only to prove the port's shape is expressible and that its three outcomes stay
/// apart. It is deliberately **local to this file** rather than added to `AudioInspectorTesting`: the
/// shared fake belongs with the adapter that needs it (task 3.7), and adding it now would be building
/// group 3's furniture inside group 2.
private struct StubDecoder: AudioDecoding {
    enum Outcome {
        case stream(PCMStreamDescription, chunks: [PCMChunk])
        case unusableFrameCount
        case failure(AudioDecodingError)
    }

    let outcome: Outcome

    func decode(
        _ file: AudioFileReference,
        chunkFrames: Int,
        receive: (PCMChunk) -> PCMChunkDisposition
    ) async throws(AudioDecodingError) -> PCMStreamDescription? {
        switch outcome {
        case let .stream(description, chunks):
            for chunk in chunks where receive(chunk) == .stop {
                return description
            }
            return description
        case .unusableFrameCount:
            return nil
        case let .failure(error):
            throw error
        }
    }
}

@Suite("Domain — the decoding port's contract")
struct AudioDecodingPortTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: nil, sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    /// The three outcomes must stay distinguishable, because they mean different things to a user: a
    /// file with no audio, a file whose length could not be established, and something going wrong.
    @Test("a readable stream comes back as a description")
    func aStreamIsDescribed() async throws {
        let description = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 2, frameCount: 1_000))
        let decoder = StubDecoder(outcome: .stream(description, chunks: []))
        let result = try await decoder.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        #expect(result == description)
    }

    /// Zero frames is a description, not an absence.
    @Test("a file with no audio is described rather than reported as absent")
    func zeroFramesIsADescription() async throws {
        let description = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 0))
        let decoder = StubDecoder(outcome: .stream(description, chunks: []))
        let result = try await decoder.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        #expect(result?.frameCount == 0)
        #expect(result != nil, "a zero-frame file is not the same as an unusable frame count")
    }

    @Test("an unusable frame count comes back as nil, not as an error")
    func unusableFrameCountIsNil() async throws {
        let decoder = StubDecoder(outcome: .unusableFrameCount)
        let result = try await decoder.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        #expect(result == nil)
    }

    @Test("a fault comes back as a typed error, not as nil")
    func faultIsAnError() async {
        let decoder = StubDecoder(outcome: .failure(
            AudioDecodingError(code: .invalidStreamDescription, message: "impossible stream")
        ))
        let error = await #expect(throws: AudioDecodingError.self) {
            try await decoder.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        }
        #expect(error?.code == .invalidStreamDescription)
    }

    /// Cancellation is an error rather than `nil`, so a cancelled read can never be mistaken for a file
    /// that offered nothing.
    @Test("cancellation is an error, never an absence")
    func cancellationIsNotAbsence() async {
        let decoder = StubDecoder(outcome: .failure(AudioDecodingError(code: .cancelled, message: "cancelled")))
        let error = await #expect(throws: AudioDecodingError.self) {
            try await decoder.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        }
        #expect(error?.code == .cancelled)
    }

    @Test("chunks arrive in file order, before the call returns")
    func chunksArriveInOrder() async throws {
        let description = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 3))
        let chunks = try (0 ..< 3).map { try PCMChunk(startFrame: $0, channels: [[Float($0)]]) }
        let decoder = StubDecoder(outcome: .stream(description, chunks: chunks))

        // The callback is synchronous and non-escaping, so it can mutate a local directly — no actor,
        // no lock, and nothing to await. That is the whole point of the shape.
        var seen: [Int] = []
        _ = try await decoder.decode(reference(), chunkFrames: 1) { chunk in
            seen.append(chunk.startFrame)
            return .continue
        }
        #expect(seen == [0, 1, 2])
    }

    /// Stopping early ends the read normally. It is not a failure, and the decoder still describes what
    /// it read.
    @Test("stopping early is not a failure")
    func stoppingEarlyIsNormal() async throws {
        let description = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 3))
        let chunks = try (0 ..< 3).map { try PCMChunk(startFrame: $0, channels: [[Float($0)]]) }
        let decoder = StubDecoder(outcome: .stream(description, chunks: chunks))

        var seen: [Int] = []
        let result = try await decoder.decode(reference(), chunkFrames: 1) { chunk in
            seen.append(chunk.startFrame)
            return .stop
        }
        #expect(seen == [0], "the decoder stopped after the first chunk")
        #expect(result == description, "and returned normally rather than throwing")
    }
}

@Suite("Domain — audio decoding error space")
struct AudioDecodingErrorTests {
    /// Every code this layer defines. Listed explicitly so adding one without deciding what it means
    /// breaks these tests rather than slipping through — the same reason `WaveformErrorTests` keeps its
    /// own list. It pins the raw values, and it claims nothing more: the type is `RawRepresentable`, so
    /// no test can enumerate it, and none here pretends that a speculative code could not be added.
    private static let allCodes: [(AudioDecodingErrorCode, String)] = [
        (.invalidStreamDescription, "decoding_invalid_stream_description"),
        (.invalidChunk, "decoding_invalid_chunk"),
        (.nonFiniteSample, "decoding_non_finite_sample"),
        (.cancelled, "decoding_cancelled"),
    ]

    @Test("each code has its stable raw value", arguments: allCodes)
    func codesAreStable(code: AudioDecodingErrorCode, rawValue: String) {
        #expect(code.rawValue == rawValue)
        #expect(AudioDecodingErrorCode(rawValue: rawValue) == code)
    }

    @Test("no two codes share a raw value")
    func codesAreDistinct() {
        let rawValues = Self.allCodes.map(\.1)
        #expect(Set(rawValues).count == rawValues.count)
        #expect(Set(Self.allCodes.map(\.0)).count == Self.allCodes.count)
    }

    /// Disjoint from **all three** of the domain's other error spaces, which is what task 2.4 asks for
    /// and what only the waveform's was previously checked against. A decoding fault says nothing about
    /// a particular visualisation, nothing about a single property and nothing about the inspection as
    /// a whole; a stable code that overlapped any of theirs would tell a caller something untrue about
    /// what failed.
    ///
    /// The prefix assertions are what make this structural rather than a coincidence of four lists: as
    /// long as this space owns `decoding_` and no other space uses it, a future addition on either side
    /// cannot collide.
    @Test("its codes collide with no other error space in the domain")
    func codesAreDisjointFromEveryOtherSpace() {
        let decoding = Set(Self.allCodes.map(\.1))

        let inspection: Set<String> = [
            InspectionErrorCode.fileOpenFailed.rawValue,
            InspectionErrorCode.fileUnreadable.rawValue,
            InspectionErrorCode.fileAccessDenied.rawValue,
        ]
        let property: Set<String> = [
            PropertyFailureCode.propertyReadError.rawValue,
        ]
        let waveform: Set<String> = [
            WaveformErrorCode.invalidConfiguration.rawValue,
            WaveformErrorCode.nonFiniteSample.rawValue,
            WaveformErrorCode.channelOutOfBounds.rawValue,
            WaveformErrorCode.frameRangeOutOfBounds.rawValue,
            WaveformErrorCode.incompleteCoverage.rawValue,
            WaveformErrorCode.cancelled.rawValue,
            WaveformErrorCode.fileAccessDenied.rawValue,
            WaveformErrorCode.fileOpenFailed.rawValue,
            WaveformErrorCode.unsupportedProcessingFormat.rawValue,
            WaveformErrorCode.readFailed.rawValue,
        ]

        #expect(decoding.isDisjoint(with: inspection))
        #expect(decoding.isDisjoint(with: property))
        #expect(decoding.isDisjoint(with: waveform))

        #expect(decoding.allSatisfy { $0.hasPrefix("decoding_") })
        #expect(inspection.union(property).union(waveform).allSatisfy { !$0.hasPrefix("decoding_") })
    }

    /// The collisions that would be easiest to cause and hardest to notice: the same *word* names a
    /// fault in two spaces, and only the prefix keeps them apart.
    @Test("codes naming the same kind of fault in another space still differ")
    func similarlyNamedCodesStayApart() {
        #expect(AudioDecodingErrorCode.nonFiniteSample.rawValue != WaveformErrorCode.nonFiniteSample.rawValue)
        #expect(AudioDecodingErrorCode.cancelled.rawValue != WaveformErrorCode.cancelled.rawValue)
    }

    @Test("the code is the identity and the message is not")
    func identityIsTheCode() {
        let one = AudioDecodingError(code: .invalidChunk, message: "one wording")
        let other = AudioDecodingError(code: .invalidChunk, message: "another wording")
        #expect(one.code == other.code)
        #expect(one != other, "the message is descriptive, so two errors with different text differ")
    }

    /// Cancellation is an error rather than an absence, deliberately: a caller who cancels has learnt
    /// nothing about their file, and reporting it as `nil` would say the file offered nothing.
    @Test("cancellation has its own code, distinct from every fault")
    func cancellationIsItsOwnOutcome() {
        #expect(AudioDecodingErrorCode.cancelled != .invalidStreamDescription)
        #expect(AudioDecodingErrorCode.cancelled != .invalidChunk)
        #expect(AudioDecodingErrorCode.cancelled.rawValue.contains("cancelled"))
    }
}
