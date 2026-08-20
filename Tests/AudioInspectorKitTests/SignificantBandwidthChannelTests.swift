import AVFoundation
import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorMedia
import Foundation
import Testing

// Task 3.4: channels are measured **separately**, and `overall` is the highest of those readings.
//
// The decision is not a matter of taste, and the fixtures below are what decided it. Combining channels
// before the threshold — by mixing, averaging or downmixing — lets opposite-polarity content cancel, and
// a measurement whose subject is *where energy stops* must not be able to lose energy the file
// genuinely carries. `SignalLevelMetricsAccumulator` and `TruePeakAccumulator` already report per
// channel plus an overall for the same reason; `LoudnessAccumulator` combines only because BS.1770
// defines programme loudness that way, and there is no such definition here.
//
// `overall` is therefore a **summary of the per-channel facts**, not a claim about "the programme".

private func measure(fileAt url: URL) async throws -> SignificantBandwidth? {
    let decoder = AVFoundationAudioDecoder(resolveURL: { _ in url })
    let file = AudioFileReference(
        displayName: url.lastPathComponent, fileExtension: url.pathExtension, sizeBytes: nil,
        modifiedAt: nil,
        source: .userSelectedLocalFile(displayName: url.lastPathComponent, locationDisclosure: .omitted)
    )
    var accumulator: SignificantBandwidthAccumulator?
    _ = try await decoder.decode(file, chunkFrames: 4_096) { stream, chunk in
        if accumulator == nil {
            accumulator = SignificantBandwidthAccumulator(sampleRate: stream.sampleRate, channelCount: stream.channelCount)
        }
        accumulator?.accumulate(chunk)
        return .continue
    }
    return accumulator?.finish()
}

private func programme(to edge: Double, level: Float = 0.01) -> AudioFixtureSignal {
    .tones(highest: edge, spacing: 500, lowest: 500, perComponentAmplitude: level)
}

private func write(
    _ signal: AudioFixtureSignal, name: String, channels: AVAudioChannelCount, in directory: URL
) throws -> URL {
    try writeAudioFixture(
        AudioFixtureSpec(
            name: name, format: .wavFloat, signal: signal, sampleRate: 48_000,
            channels: channels, frames: 48_000
        ),
        in: directory
    )
}

private func near(_ channel: SignificantBandwidth.Channel?, _ edge: Double) -> Bool {
    guard let channel else { return false }
    let error = channel.frequency - edge
    return error >= -channel.resolution && error <= 5 * channel.resolution
}

@Suite("Analysis — significant bandwidth measures channels apart")
struct SignificantBandwidthChannelTests {

    @Test("mono reports one channel and an overall equal to it")
    func mono() async throws {
        try await withTemporaryDirectory { directory in
            let measurement = try #require(try await measure(fileAt: write(programme(to: 16_000), name: "mono", channels: 1, in: directory)))
            #expect(measurement.channels.count == 1)
            #expect(measurement.overall == measurement.channels[0])
            #expect(near(measurement.overall, 16_000))
        }
    }

    @Test("two identical channels read identically")
    func identicalStereo() async throws {
        try await withTemporaryDirectory { directory in
            let measurement = try #require(try await measure(fileAt: write(programme(to: 16_000), name: "same", channels: 2, in: directory)))
            #expect(measurement.channels.count == 2)
            #expect(measurement.channels[0] == measurement.channels[1])
            #expect(near(measurement.overall, 16_000))
        }
    }

    /// The case that decides the shape of the result: two different facts about two channels, and a
    /// single number could only report one of them.
    @Test("channels with different extents are reported separately, and overall is the higher")
    func differentExtents() async throws {
        try await withTemporaryDirectory { directory in
            let measurement = try #require(try await measure(fileAt: write(
                .perChannel([programme(to: 16_000), programme(to: 20_000)]), name: "split", channels: 2, in: directory
            )))
            #expect(near(measurement.channels[0], 16_000), "channel 0 read \(String(describing: measurement.channels[0]))")
            #expect(near(measurement.channels[1], 20_000), "channel 1 read \(String(describing: measurement.channels[1]))")
            #expect(near(measurement.overall, 20_000))
        }
    }

    /// **The fixture that rules out combining.** Identical content with the sign flipped on odd
    /// channels: any downmix that sums the channels cancels it to a flat line, and a measurement built
    /// on that would report an absence for a file that is plainly not silent.
    @Test("opposite polarity does not cancel, because the channels are never summed")
    func oppositePolarity() async throws {
        try await withTemporaryDirectory { directory in
            let measurement = try #require(try await measure(fileAt: write(
                .oppositePolarity(frequency: 15_000, amplitude: 0.4), name: "polarity", channels: 2, in: directory
            )))
            #expect(near(measurement.channels[0], 15_000))
            #expect(near(measurement.channels[1], 15_000))
            #expect(near(measurement.overall, 15_000), "a downmix would have cancelled this file to silence")
        }
    }

    /// A weak but persistent band in one channel only. It must survive in that channel's own reading,
    /// and `overall` must carry it — a per-channel measurement that a summary then discarded would be
    /// no better than a downmix.
    @Test("a weak band present in one channel only survives in that channel and in overall")
    func bandInOneChannel() async throws {
        try await withTemporaryDirectory { directory in
            let band = AudioFixtureSignal.tones(
                highest: 20_000, spacing: 500, lowest: 19_000,
                perComponentAmplitude: 0.01 * Float(pow(10.0, -30.0 / 20))
            )
            let measurement = try #require(try await measure(fileAt: write(
                .perChannel([.sum([programme(to: 16_000), band]), programme(to: 16_000)]),
                name: "one-channel-band", channels: 2, in: directory
            )))
            #expect(near(measurement.channels[0], 20_000))
            #expect(near(measurement.channels[1], 16_000))
            #expect(near(measurement.overall, 20_000))
        }
    }

    /// **No layout is asserted, and more than two channels are not a special case.** Four channels with
    /// four different extents are four readings by index; nothing here names a front, a centre or an
    /// LFE, because the pipeline reads channel counts and never labels.
    @Test("four channels are four readings, by index and with no layout")
    func fourChannels() async throws {
        try await withTemporaryDirectory { directory in
            let measurement = try #require(try await measure(fileAt: write(
                .perChannel([programme(to: 8_000), programme(to: 12_000), programme(to: 16_000), programme(to: 20_000)]),
                name: "quad", channels: 4, in: directory
            )))
            #expect(measurement.channels.count == 4)
            for (index, edge) in [8_000.0, 12_000, 16_000, 20_000].enumerated() {
                #expect(near(measurement.channels[index], edge), "channel \(index) read \(String(describing: measurement.channels[index]))")
            }
            #expect(near(measurement.overall, 20_000))
        }
    }

    /// **The programme budget is a property of the file, not of a channel.** A channel sitting 70 dB
    /// under the rest is below the programme, so it is not measured — and its `nil` is a fact about the
    /// file's dynamics, not a defect. Measuring it against its own peak instead would make a channel of
    /// pure dither report its own noise floor's bandwidth.
    @Test("a channel far below the programme is not measured")
    func channelBelowTheBudget() async throws {
        try await withTemporaryDirectory { directory in
            let measurement = try #require(try await measure(fileAt: write(
                .perChannel([programme(to: 16_000, level: 0.02), programme(to: 20_000, level: 0.02 * Float(pow(10.0, -70.0 / 20)))]),
                name: "quiet-channel", channels: 2, in: directory
            )))
            #expect(near(measurement.channels[0], 16_000))
            #expect(measurement.channels[1] == nil, "a channel 70 dB under the programme read \(String(describing: measurement.channels[1]))")
            #expect(near(measurement.overall, 16_000))
        }
    }
}

// MARK: - The stratification's declared tolerance

@Suite("Analysis — significant bandwidth: the budget boundary and its stratification")
struct SignificantBandwidthBudgetBoundaryTests {

    /// Phase 4's adversarial case, pinned. The counters are stratified in 0.25 dB steps, so the stratum
    /// straddling `filePeak − 60 dB` cannot be split. It is resolved **inclusively**, which means a
    /// passage sitting exactly on the budget is measured — and one a quarter of a decibel below it may
    /// be too. Both sides of that are asserted here so the tolerance cannot drift unnoticed.
    @Test("a passage on either side of the budget boundary", arguments: [-59.5, -60.0, -60.5, -61.0, -65.0])
    func boundary(down: Double) async throws {
        try await withTemporaryDirectory { directory in
            let half = 24_000
            let gain = Float(pow(10.0, down / 20))
            let band = AudioFixtureSignal.tones(
                highest: 20_000, spacing: 500, lowest: 19_000,
                perComponentAmplitude: 0.01 * gain * Float(pow(10.0, -30.0 / 20))
            )
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "boundary-\(Int(-down * 10))", format: .wavFloat,
                    signal: .sum([
                        .enveloped(programme(to: 16_000), segments: [.init(amplitude: 1, frames: half)], rampFrames: 256),
                        .enveloped(
                            .sum([programme(to: 16_000, level: 0.01 * gain), band]),
                            segments: [.init(amplitude: 0, frames: half), .init(amplitude: 1, frames: half)], rampFrames: 256
                        ),
                    ]),
                    sampleRate: 48_000, channels: 1, frames: 48_000
                ),
                in: directory
            )
            let measurement = try #require(try await measure(fileAt: url))
            let frequency = measurement.overall?.frequency ?? 0
            // Inside the budget, or within the one stratum the structure cannot split: measured.
            // Clearly below it: not measured. -60.5 is the first value beyond both.
            if down >= -60.0 {
                #expect(frequency > 19_000, "a passage \(down) dB down should be measured; read \(frequency)")
            } else if down <= -60.5 {
                #expect(frequency < 17_000, "a passage \(down) dB down is below the budget; read \(frequency)")
            }
        }
    }
}
