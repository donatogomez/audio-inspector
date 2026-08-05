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
        let decoder = StubDecoder(outcome: .failure(AudioDecodingError(code: .incompleteCoverage, message: "short")))
        let error = await #expect(throws: AudioDecodingError.self) {
            try await decoder.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        }
        #expect(error?.code == .incompleteCoverage)
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
    /// Disjoint from every other error space in the domain. A decoding fault says nothing about a
    /// particular visualisation, and a stable code that overlapped another's would tell a caller
    /// something untrue about what failed.
    @Test("its codes do not collide with the waveform's or the inspection's")
    func codesAreDisjoint() {
        let decoding: Set<String> = [
            AudioDecodingErrorCode.invalidStreamDescription.rawValue,
            AudioDecodingErrorCode.invalidChunk.rawValue,
            AudioDecodingErrorCode.nonFiniteSample.rawValue,
            AudioDecodingErrorCode.frameRangeOutOfBounds.rawValue,
            AudioDecodingErrorCode.incompleteCoverage.rawValue,
            AudioDecodingErrorCode.cancelled.rawValue,
        ]
        let waveform: Set<String> = [
            WaveformErrorCode.invalidConfiguration.rawValue,
            WaveformErrorCode.nonFiniteSample.rawValue,
            WaveformErrorCode.frameRangeOutOfBounds.rawValue,
            WaveformErrorCode.incompleteCoverage.rawValue,
            WaveformErrorCode.cancelled.rawValue,
            WaveformErrorCode.readFailed.rawValue,
        ]
        #expect(decoding.isDisjoint(with: waveform))
        #expect(decoding.count == 6, "every code is distinct from its siblings")
    }

    /// No `fileOpenFailed`, no `readFailed`: no adapter exists to raise them yet, and a stable code
    /// with no producer promises behaviour nobody has written.
    @Test("no code exists for a failure this layer cannot yet produce")
    func noSpeculativeCodes() {
        let declared = [
            AudioDecodingErrorCode.invalidStreamDescription.rawValue,
            AudioDecodingErrorCode.invalidChunk.rawValue,
            AudioDecodingErrorCode.nonFiniteSample.rawValue,
            AudioDecodingErrorCode.frameRangeOutOfBounds.rawValue,
            AudioDecodingErrorCode.incompleteCoverage.rawValue,
            AudioDecodingErrorCode.cancelled.rawValue,
        ]
        for code in declared {
            #expect(!code.contains("open"))
            #expect(!code.contains("access"))
            #expect(!code.contains("unsupported"))
        }
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
        #expect(AudioDecodingErrorCode.cancelled != .incompleteCoverage)
        #expect(AudioDecodingErrorCode.cancelled != .invalidChunk)
        #expect(AudioDecodingErrorCode.cancelled.rawValue.contains("cancelled"))
    }
}
