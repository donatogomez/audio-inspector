import AVFoundation
import Foundation
import Testing

// Each constant of the method, shown to be load-bearing by breaking it.
//
// A suite of passing assertions proves that the chosen values work; it does not prove they were
// needed. These do: every test below changes exactly one constant and names the fixture that stops
// being measured correctly. If one of these ever passes with the constant changed, either the
// constant is doing nothing or the fixture stopped testing it.

private func programme(to edge: Double, level: Float = 0.01) -> AudioFixtureSignal {
    .tones(highest: edge, spacing: 500, lowest: 500, perComponentAmplitude: level)
}

private func highBand(relativeDB: Double, programmeLevel: Float = 0.01) -> AudioFixtureSignal {
    .tones(
        highest: 20_000, spacing: 500, lowest: 19_000,
        perComponentAmplitude: programmeLevel * Float(pow(10.0, relativeDB / 20))
    )
}

private func write(
    _ signal: AudioFixtureSignal, name: String, sampleRate: Double = 48_000,
    frames: AVAudioFrameCount = 48_000, in directory: URL
) throws -> URL {
    try writeAudioFixture(
        AudioFixtureSpec(
            name: name, format: .wavFloat, signal: signal,
            sampleRate: sampleRate, channels: 1, frames: frames
        ),
        in: directory
    )
}

@Suite("Analysis — programme bandwidth: every constant is load-bearing")
struct ProgrammeBandwidthNegativeControlTests {

    /// Half a second of programme, then half a second 70 dB lower carrying a real 19–20 kHz band.
    /// The 60 dB budget excludes the quiet half; widening it to 80 dB admits it.
    @Test("widening the 60 dB budget admits a passage the declared cost excludes")
    func budgetIsLoadBearing() async throws {
        try await withTemporaryDirectory { directory in
            let half = 24_000, gain = Float(pow(10.0, -70.0 / 20))
            let url = try write(
                .sum([
                    .enveloped(programme(to: 16_000), segments: [.init(amplitude: 1, frames: half)], rampFrames: 256),
                    .enveloped(
                        .sum([programme(to: 16_000, level: 0.01 * gain), highBand(relativeDB: -30, programmeLevel: 0.01 * gain)]),
                        segments: [.init(amplitude: 0, frames: half), .init(amplitude: 1, frames: half)],
                        rampFrames: 256
                    ),
                ]),
                name: "nc-budget", in: directory
            )
            let declared = try #require(try await measureProgrammeBandwidth(of: url).readings.first ?? nil)
            var widened = ProgrammeBandwidthOverrides(); widened.budgetDB = -80
            let admitted = try #require(try await measureProgrammeBandwidth(of: url, overrides: widened).readings.first ?? nil)
            #expect(declared.frequency < 17_000, "the declared budget should exclude the quiet passage")
            #expect(admitted.frequency > 19_000, "an 80 dB budget should admit it — the constant does nothing")
        }
    }

    /// A real band 40 dB below the programme is inside the −50 dB threshold and outside a −30 dB one.
    @Test("tightening the threshold to -30 dB loses a real band the method reports")
    func thresholdIsLoadBearing() async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(.sum([programme(to: 16_000), highBand(relativeDB: -40)]), name: "nc-threshold", in: directory)
            let declared = try #require(try await measureProgrammeBandwidth(of: url).readings.first ?? nil)
            var tightened = ProgrammeBandwidthOverrides(); tightened.thresholdDB = -30
            let lost = try #require(try await measureProgrammeBandwidth(of: url, overrides: tightened).readings.first ?? nil)
            #expect(declared.frequency > 19_000)
            #expect(lost.frequency < 17_000, "a -30 dB threshold should drop a band 40 dB down")
        }
    }

    /// A band present for a twentieth of the file is rejected at 10 % and admitted at 1 %.
    @Test("dropping persistence to 1 % admits a band present a twentieth of the time")
    func persistenceIsLoadBearing() async throws {
        try await withTemporaryDirectory { directory in
            let frames = 48_000, on = frames / 20
            let url = try write(
                .sum([
                    programme(to: 16_000),
                    .enveloped(
                        highBand(relativeDB: -30),
                        segments: [.init(amplitude: 1, frames: on), .init(amplitude: 0, frames: frames - on)],
                        rampFrames: 256
                    ),
                ]),
                name: "nc-persistence", in: directory
            )
            let declared = try #require(try await measureProgrammeBandwidth(of: url).readings.first ?? nil)
            var relaxed = ProgrammeBandwidthOverrides(); relaxed.persistenceFraction = 0.01
            let admitted = try #require(try await measureProgrammeBandwidth(of: url, overrides: relaxed).readings.first ?? nil)
            #expect(declared.frequency < 17_000)
            #expect(admitted.frequency > 19_000, "1 % persistence should admit a band present 5 % of the time")
        }
    }

    /// **The control that pins the correction group 1 part D made.** A magnitude floor turns a window
    /// of zeros into a window at the floor — one with a spectral peak, and therefore a reference —
    /// which is exactly why the spike's first harness needed an absolute silence rule and the method
    /// does not.
    @Test("reintroducing a magnitude clamp stops silence being an absence")
    func theAbsenceOfAClampIsLoadBearing() async throws {
        try await withTemporaryDirectory { directory in
            let url = try write(.silence, name: "nc-clamp", in: directory)
            #expect(
                (try await measureProgrammeBandwidth(of: url).readings.first ?? nil) == nil,
                "unclamped, silence must be an absence"
            )
            var clamped = ProgrammeBandwidthOverrides(); clamped.magnitudeClamp = 1e-12
            let reading = try await measureProgrammeBandwidth(of: url, overrides: clamped).readings.first ?? nil
            #expect(reading != nil, "with a clamp, silence produces a reading — which is the failure the method avoids")
            #expect(reading?.frequency ?? 0 > 20_000, "and the reading it produces is the top of the band")
        }
    }

    /// A window fixed in **samples** makes the persistence criterion rate-dependent. Ten short bursts
    /// totalling a twentieth of a file are the same temporal evidence at every rate; time-locked they
    /// are classified the same way, sample-locked they are not.
    ///
    /// The duty cycle matters and is not free to choose: at 10 % the smear puts every rate above the
    /// criterion and both families agree, which proves nothing. 5 % is the fraction group 1 measured
    /// as the one that separates them (spike §12.5).
    @Test("a sample-locked window makes two rates disagree about the same evidence")
    func timeLockingIsLoadBearing() async throws {
        try await withTemporaryDirectory { directory in
            var timeLocked: [Bool] = [], sampleLocked: [Bool] = []
            for rate in [48_000.0, 192_000.0] {
                let frames = Int(rate)
                let bursts = 10, on = frames / 20 / bursts
                var segments: [AudioFixtureSegment] = []
                for _ in 0 ..< bursts {
                    segments.append(.init(amplitude: 1, frames: on))
                    segments.append(.init(amplitude: 0, frames: frames / bursts - on))
                }
                let url = try write(
                    .sum([programme(to: 16_000), .enveloped(highBand(relativeDB: -30), segments: segments, rampFrames: 64)]),
                    name: "nc-lock-\(Int(rate))", sampleRate: rate, frames: AVAudioFrameCount(frames), in: directory
                )
                let locked = try #require(try await measureProgrammeBandwidth(of: url).readings.first ?? nil)
                var fixed = ProgrammeBandwidthOverrides(); fixed.fixedFFTSize = 2_048
                let unlocked = try #require(try await measureProgrammeBandwidth(of: url, overrides: fixed).readings.first ?? nil)
                timeLocked.append(locked.frequency > 19_000)
                sampleLocked.append(unlocked.frequency > 19_000)
            }
            #expect(
                timeLocked[0] == timeLocked[1],
                "time-locked, 48 and 192 kHz disagreed about the same evidence: \(timeLocked)"
            )
            #expect(
                sampleLocked[0] != sampleLocked[1],
                "sample-locked, 48 and 192 kHz agreed — the fixture no longer separates the two families"
            )
        }
    }
}
