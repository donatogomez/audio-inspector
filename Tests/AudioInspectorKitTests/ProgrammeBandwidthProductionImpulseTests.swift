import AVFoundation
import Foundation
import Testing

import FeatureImport

// **Task 6.2, against production, and the first of ADR-0023's two promotion conditions.**
//
// The control does not exist to show that a click is bad. It exists to show that **an isolated spectral
// burst is not mistaken for persistent programme bandwidth** — that the persistence criterion, running
// in the real pipeline, separates a transient from an extent.
//
// ## What this suite corrects
//
// Task 6.2 was written as "a file silent but for one click reports no wider a band than silence does",
// and that prediction is **false** — measured, not argued, and known to be false before this suite
// existed: `ProgrammeBandwidthEvidenceTests.impulseAloneInSilence` records it for the reference method
// and ADR-0023's consequences record it as a declared limitation. The reason is the eligibility rule.
// A window carrying no energy is not an observation and is filed nowhere, so in a file that is silence
// plus one click the *only* eligible windows are the ones the click touches. The click is then present
// in 100 % of them, and a click is broadband. It is not a transient *within* a programme — it **is**
// the programme.
//
// Production agrees with the reference exactly, which is what this suite pins. The honest control is
// the one below it: inside a real programme, an isolated impulse does not move the reading.
@Suite("App — programme bandwidth and isolated transients, through production")
struct ProgrammeBandwidthProductionImpulseTests {

    private let rate = 48_000.0
    /// Three seconds, so the eligible-window count is large enough for a 10 % share to be several
    /// windows rather than one. See `impulsesNeededToReachPersistence`.
    private var frames: AVAudioFrameCount { AVAudioFrameCount(rate * 3) }

    /// One impulse lights exactly the windows that contain it: the window is 2 048 frames and the hop
    /// is a quarter of it, so a lone sample falls inside **four** consecutive windows.
    private let windowsPerImpulse = 4

    /// The windows a three-second file yields at 48 kHz: `floor((144 000 − 2 048) / 512) + 1`.
    /// With a programme running throughout, every one of them is eligible.
    private let eligibleWindows = 278

    /// `ceil(0.10 × 278) = 28` windows must carry a bin for it to be reported. Four windows per
    /// impulse would put the turnover at seven — and **measured through production it is eight**, which
    /// is worth stating rather than rounding away.
    ///
    /// The extra impulse is the Hann taper. Of the four windows a lone sample falls inside, the
    /// outermost carries it close to a window edge, where the window's own coefficient is near zero:
    /// that window is attenuated far enough that the click's bins do not clear the significance
    /// threshold, so an impulse contributes about three and a half windows rather than four. Eight
    /// impulses reach 28, seven do not. Both sides are asserted, so this discriminates rather than
    /// confirms.
    private let impulsesUnderPersistence = 7
    private let impulsesOverPersistence = 8

    /// Impulses spread evenly, far enough apart that no window contains two.
    private func impulseTrain(_ count: Int) -> [AudioFixtureSignal] {
        let total = Int(frames)
        return (0 ..< count).map { .impulse(amplitude: 0.9, frameIndex: total / (count + 1) * ($0 + 1)) }
    }

    // MARK: Silence and a click are two different answers, for two different reasons

    /// Digital silence carries **no eligible window at all**, so there is nothing to report and the
    /// composition publishes an absence.
    @Test("digital silence publishes no programme bandwidth")
    func silenceIsAnAbsence() async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("silence", .silence, rate: rate, frames: frames), in: directory
            )
            #expect(outcome == .unavailable, "digital silence published \(outcome)")
        }
    }

    /// **The declared limitation, asserted through production so it cannot be rediscovered.**
    ///
    /// Silence plus one click is *not* the same answer as silence, and the difference is the whole
    /// mechanism: silence has no eligible window, while the click makes four of them eligible and is
    /// present in all four. A hundred per cent of the eligible windows clears any persistence
    /// criterion, and a click is broadband, so the reading is the top of the band.
    ///
    /// This is deliberately kept as its own test rather than folded into a helper beside the silence
    /// case. The two absences would look alike through one predicate, and only one of them is an
    /// absence at all.
    @Test("a click alone in silence is the programme, and reads broadband — the declared limitation")
    func impulseAloneInSilenceReadsBroadband() async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("impulse-alone", .impulse(amplitude: 0.9, frameIndex: 24_000),
                               rate: rate, frames: frames),
                in: directory
            )
            let overall = try #require(
                productionReading(outcome, "a click alone in silence"),
                "a click alone in silence published no measurement"
            )
            let reading = try #require(overall, "a click alone in silence published no reading")
            #expect(
                reading.frequency > 20_000,
                """
                a click alone in silence read \(reading.frequency) Hz through production; \
                the limitation ADR-0023 declares has changed and the record must be revisited
                """
            )
            #expect(outcome != .unavailable, "this case is a reading, not an absence — that is the point")
        }
    }

    // MARK: The control the design exists for

    /// **The property.** An isolated full-scale click inside a real programme must not widen the
    /// reported band by so much as a bin: four windows out of 278 is 1.4 %, far under the 10 % the
    /// criterion requires.
    ///
    /// Asserted as *equality with the undisturbed programme* rather than merely "near 16 kHz", because
    /// a control that allowed the reading to drift within a tolerance would pass while the transient
    /// was in fact moving it.
    @Test("an isolated click inside a programme does not move the reading at all")
    func impulseInsideProgrammeChangesNothing() async throws {
        try await withTemporaryDirectory { directory in
            let clean = try await measureThroughProduction(
                productionSpec("prog-clean", productionProgramme(to: 16_000), rate: rate, frames: frames),
                in: directory
            )
            let clicked = try await measureThroughProduction(
                productionSpec("prog-clicked",
                               .sum([productionProgramme(to: 16_000)] + impulseTrain(1)),
                               rate: rate, frames: frames),
                in: directory
            )
            try expectProductionEdge(clean, at: 16_000, "a 16 kHz programme")
            try expectProductionEdge(clicked, at: 16_000, "a 16 kHz programme with one click in it")
            #expect(clicked == clean, "one click changed a 16 kHz programme's reading")
        }
    }

    /// **The boundary, from the criterion rather than from a run.** Six impulses light 24 of 278
    /// windows — 8.6 %, under the threshold — and seven light 28, which is exactly the `ceil(10 % · N)`
    /// the method requires. Both sides are asserted, so the test discriminates rather than confirms.
    ///
    /// This is what makes "isolated" a measured word instead of an adjective: the reading does not
    /// change because the burst is short, it changes when the burst stops being rare.
    @Test("the reading turns over where the persistence criterion puts it, and not before")
    func persistenceBoundaryForImpulseTrains() async throws {
        try await withTemporaryDirectory { directory in
            let needed = Int(ceil(0.10 * Double(eligibleWindows)))
            #expect(needed == 28, "the criterion's arithmetic changed: \(needed) windows needed")

            let under = try await measureThroughProduction(
                productionSpec("train-under",
                               .sum([productionProgramme(to: 16_000)] + impulseTrain(impulsesUnderPersistence)),
                               rate: rate, frames: frames),
                in: directory
            )
            try expectProductionEdge(
                under, at: 16_000,
                """
                \(impulsesUnderPersistence) clicks in a 16 kHz programme moved the reading, though they \
                do not reach \(needed) of \(eligibleWindows) windows
                """
            )

            let over = try await measureThroughProduction(
                productionSpec("train-over",
                               .sum([productionProgramme(to: 16_000)] + impulseTrain(impulsesOverPersistence)),
                               rate: rate, frames: frames),
                in: directory
            )
            let overall = try #require(
                productionReading(over, "\(impulsesOverPersistence) clicks"), "no measurement"
            )
            let reading = try #require(overall, "no reading")
            #expect(
                reading.frequency > 20_000,
                """
                \(impulsesOverPersistence) clicks reach \(needed) of \(eligibleWindows) windows, which \
                meets the criterion, yet the reading stayed at \(reading.frequency) Hz
                """
            )
        }
    }

    /// Whether the clicks are spread across the file or packed together changes nothing, because the
    /// criterion counts windows and not spacing. Recorded because "clustered transients" is exactly the
    /// kind of case a reader assumes was overlooked.
    @Test("clustering the clicks does not change the answer, because the criterion counts windows")
    func clusteringDoesNotMatter() async throws {
        try await withTemporaryDirectory { directory in
            let spread = try await measureThroughProduction(
                productionSpec("spread", .sum([productionProgramme(to: 16_000)] + impulseTrain(3)),
                               rate: rate, frames: frames),
                in: directory
            )
            let packed = try await measureThroughProduction(
                productionSpec("packed",
                               .sum([productionProgramme(to: 16_000)]
                                   + (0 ..< 3).map { .impulse(amplitude: 0.9, frameIndex: 24_000 + $0 * 4_096) }),
                               rate: rate, frames: frames),
                in: directory
            )
            try expectProductionEdge(spread, at: 16_000, "three clicks spread through a programme")
            try expectProductionEdge(packed, at: 16_000, "three clicks packed together in a programme")
            #expect(spread == packed, "the answer depended on where the clicks sat, not how many windows they lit")
        }
    }
}
