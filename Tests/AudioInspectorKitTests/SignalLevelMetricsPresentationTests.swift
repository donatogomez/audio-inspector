import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureAnalysis
import FeatureImport

/// What the signal levels surface must keep, asserted over the pure formatter and copy rather than over
/// a rendering — the same discipline `WaveformPresentationTests`/`SpectrogramCopyTests` already apply.
@Suite("Feature — signal level metrics presentation")
struct SignalLevelMetricsPresentationTests {

    // MARK: - Fixtures

    private func channel(
        sampleCount: Int = 44_100,
        peak: Float? = 0.5,
        rms: Float? = 0.25,
        dcOffset: Float? = 0.001,
        clipped: Int = 0
    ) -> SignalLevelMetrics.Channel {
        SignalLevelMetrics.Channel(
            sampleCount: sampleCount, peakSample: peak, rms: rms, dcOffset: dcOffset, clippedSampleCount: clipped
        )
    }

    private func metrics(
        channels: [SignalLevelMetrics.Channel],
        overallPeak: Float?,
        overallRMS: Float?,
        overallDCOffset: Float?,
        overallClipped: Int
    ) -> SignalLevelMetrics {
        SignalLevelMetrics(
            channels: channels,
            overallPeakSample: overallPeak,
            overallRMS: overallRMS,
            overallDCOffset: overallDCOffset,
            overallClippedSampleCount: overallClipped
        )
    }

    /// A single, ordinary mono reading: nothing zero, nothing clipped, nothing absent.
    private var monoMetrics: SignalLevelMetrics {
        metrics(channels: [channel()], overallPeak: 0.5, overallRMS: 0.25, overallDCOffset: 0.001, overallClipped: 0)
    }

    /// Two distinguishable channels, so a per-channel breakdown is meaningful rather than a repeat of
    /// the overall figure.
    private var stereoMetrics: SignalLevelMetrics {
        let left = channel(peak: 0.708, rms: 0.3, dcOffset: 0.002, clipped: 3)
        let right = channel(peak: 0.5, rms: 0.2, dcOffset: -0.001, clipped: 0)
        return metrics(
            channels: [left, right], overallPeak: 0.708, overallRMS: 0.25, overallDCOffset: 0.0005, overallClipped: 3
        )
    }

    /// A file with no audio frames at all: every per-sample value is not computable, but the clip count
    /// is still a genuine, defined zero.
    private var zeroFrameMetrics: SignalLevelMetrics {
        let empty = channel(sampleCount: 0, peak: nil, rms: nil, dcOffset: nil, clipped: 0)
        return metrics(channels: [empty], overallPeak: nil, overallRMS: nil, overallDCOffset: nil, overallClipped: 0)
    }

    /// Real, computed silence — distinct from `zeroFrameMetrics`: `sampleCount > 0`, every value a
    /// genuine zero rather than absent.
    private var silentMetrics: SignalLevelMetrics {
        let silent = channel(peak: 0, rms: 0, dcOffset: 0, clipped: 0)
        return metrics(channels: [silent], overallPeak: 0, overallRMS: 0, overallDCOffset: 0, overallClipped: 0)
    }

    // MARK: - Rows: values and units

    @Test func peakAndRMSReadInDecibelsFullScale() {
        let rows = SignalLevelMetricsCopy.rows(for: monoMetrics)
        let peak = try! #require(rows.first { $0.name == "Peak sample" })
        let rms = try! #require(rows.first { $0.name == "RMS level" })
        #expect(peak.value == HumanFormat.decibelsFullScale(0.5))
        #expect(rms.value == HumanFormat.decibelsFullScale(0.25))
    }

    @Test func dcOffsetReadsAsALinearSignedValueNeverInDecibels() {
        let rows = SignalLevelMetricsCopy.rows(for: monoMetrics)
        let dc = try! #require(rows.first { $0.name == "DC offset" })
        #expect(dc.value == HumanFormat.linearOffset(0.001))
        #expect(dc.value?.contains("dBFS") == false)
    }

    @Test func clippedSamplesReadAsAPlainCount() {
        let many = metrics(channels: [channel(clipped: 12_431)], overallPeak: 0.1, overallRMS: 0.05, overallDCOffset: 0, overallClipped: 12_431)
        let rows = SignalLevelMetricsCopy.rows(for: many)
        let clipped = try! #require(rows.first { $0.name == "Clipped samples" })
        #expect(clipped.value == "12,431")
        #expect(clipped.detail?.contains("Samples at or beyond full scale.") == true)
    }

    @Test func aRealZeroClipCountIsShownAsZeroNeverAsAbsent() {
        let rows = SignalLevelMetricsCopy.rows(for: monoMetrics)
        let clipped = try! #require(rows.first { $0.name == "Clipped samples" })
        #expect(clipped.value == "0")
    }

    // MARK: - Zero frames vs a genuine computed zero

    /// A file with no frames reports every per-sample metric as not computable — never a fabricated
    /// zero, and never a bare dash with no explanation.
    @Test func zeroFramesReportsNotComputableRatherThanZero() {
        let rows = SignalLevelMetricsCopy.rows(for: zeroFrameMetrics)
        for name in ["Peak sample", "RMS level", "DC offset"] {
            let row = try! #require(rows.first { $0.name == name })
            #expect(row.value == nil, "\(name) fabricated a value for zero frames")
            #expect(row.detail?.contains("Not computable") == true, "\(name) lost the not-computable reason")
        }
    }

    /// Real silence — the file was measured and every sample was exactly zero — is a genuine computed
    /// value, distinct from "not computable," and must read as the floored dBFS figure, not as absence.
    @Test func realSilenceIsAComputedValueNotAnAbsence() {
        let rows = SignalLevelMetricsCopy.rows(for: silentMetrics)
        let peak = try! #require(rows.first { $0.name == "Peak sample" })
        #expect(peak.value == HumanFormat.decibelsFullScale(0)) // floored, not "not computable"
        #expect(peak.detail?.contains("Not computable") != true)
    }

    /// The clip count is always defined, even for a channel with no samples — it never shares the other
    /// three metrics' "not computable" state.
    @Test func clipCountIsAlwaysDefinedEvenForZeroFrames() {
        let rows = SignalLevelMetricsCopy.rows(for: zeroFrameMetrics)
        let clipped = try! #require(rows.first { $0.name == "Clipped samples" })
        #expect(clipped.value == "0")
        #expect(clipped.detail?.contains("Not computable") != true)
    }

    // MARK: - Per-channel vs overall

    /// A single channel repeats no information in a detail line: the overall figure already is the only
    /// channel's figure.
    @Test func aSingleChannelShowsNoPerChannelBreakdown() {
        let rows = SignalLevelMetricsCopy.rows(for: monoMetrics)
        for row in rows {
            #expect(row.detail?.contains("Channel") != true, "\(row.name) repeated itself as a per-channel row")
        }
    }

    /// More than one channel earns a breakdown, because an asymmetry between channels is exactly the
    /// kind of fact an overall-only figure would hide.
    @Test func multipleChannelsShowThePerChannelBreakdown() {
        let rows = SignalLevelMetricsCopy.rows(for: stereoMetrics)
        let peak = try! #require(rows.first { $0.name == "Peak sample" })
        #expect(peak.detail == "Channel 1: \(HumanFormat.decibelsFullScale(0.708)) · Channel 2: \(HumanFormat.decibelsFullScale(0.5))")
    }

    /// Channels are never named `Left`/`Right`: the domain reports a count, never a layout, and naming a
    /// pair would assert a configuration nothing here ever read.
    @Test func channelsAreNeverNamedByAssumedLayout() {
        let rows = SignalLevelMetricsCopy.rows(for: stereoMetrics)
        for row in rows {
            let text = [row.value, row.detail].compactMap { $0 }.joined()
            #expect(!text.contains("Left"), "\(row.name) assumed a stereo layout")
            #expect(!text.contains("Right"), "\(row.name) assumed a stereo layout")
        }
    }

    /// Three or more channels stay legible: every channel appears exactly once, numbered rather than
    /// named.
    @Test func multichannelStaysLegibleAndNumbersEveryChannel() {
        let six = metrics(
            channels: (1 ... 6).map { channel(peak: Float($0) / 10) },
            overallPeak: 0.6, overallRMS: 0.25, overallDCOffset: 0.001, overallClipped: 0
        )
        let rows = SignalLevelMetricsCopy.rows(for: six)
        let peak = try! #require(rows.first { $0.name == "Peak sample" })
        for index in 1 ... 6 {
            #expect(peak.detail?.contains("Channel \(index):") == true)
        }
    }

    // MARK: - The words, in every state

    private var everyState: [SignalLevelMetricsPresentation] {
        [.loading, .metrics(monoMetrics), .metrics(zeroFrameMetrics), .absent, .failed(message: "The signal level metrics for this file could not be produced.")]
    }

    @Test func loadingSaysMetricsAreBeingPreparedAndNothingAboutTheFile() {
        let text = try! #require(SignalLevelMetricsCopy.text(for: .loading))
        #expect(text.headline == "Preparing the signal levels…")
        #expect(text.accessibilityLabel == "Signal levels. Preparing the signal levels.")
    }

    @Test func metricsProduceNoSectionLevelTextOnlyRows() {
        #expect(SignalLevelMetricsCopy.text(for: .metrics(monoMetrics)) == nil)
    }

    @Test func anAbsentReadingIsStatedInWordsAndClearsTheRestOfTheReport() {
        let text = try! #require(SignalLevelMetricsCopy.text(for: .absent))
        #expect(text.headline == "No signal level metrics for this file.")
        #expect(text.detail?.contains("Everything else in this report is unchanged") == true)
    }

    @Test func aFailureIsAboutMeasuringAndNotAboutTheAudio() {
        let message = "The signal level metrics for this file could not be produced."
        let text = try! #require(SignalLevelMetricsCopy.text(for: .failed(message: message)))
        #expect(text.headline == message)
        #expect(text.detail?.contains("not something read from the audio") == true)
        #expect(text.detail?.contains("Everything else in this report is unchanged") == true)
    }

    // MARK: - Nothing presented judges the audio, and nothing internal escapes

    private func allRowText(_ metrics: SignalLevelMetrics) -> [String] {
        SignalLevelMetricsCopy.rows(for: metrics).flatMap { [$0.name, $0.value, $0.detail, $0.accessibilityLabel] }.compactMap { $0 }
    }

    private func allStateText(_ presentation: SignalLevelMetricsPresentation) -> [String] {
        guard let text = SignalLevelMetricsCopy.text(for: presentation) else { return [] }
        return [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 } + [SignalLevelMetricsCopy.title]
    }

    /// The vocabulary the accepted requirement names explicitly, plus the one phrase this slice singles
    /// out by name: clipping is a count, never a diagnosis.
    @Test func noSignalLevelTextCharacterisesTheSignal() {
        let forbidden: Set<String> = [
            "good", "bad", "healthy", "damaged", "poor", "excellent", "clean", "distorted", "problematic",
            "safe", "unsafe", "quality", "better", "worse", "loud", "quiet", "compressed", "dynamic", "hot", "flat",
        ]
        var texts = allStateText(.loading) + allStateText(.absent)
            + allStateText(.failed(message: "The signal level metrics for this file could not be produced."))
        texts += allRowText(monoMetrics) + allRowText(stereoMetrics) + allRowText(zeroFrameMetrics) + allRowText(silentMetrics)
        for text in texts {
            let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
            let offending = words.intersection(forbidden)
            #expect(offending.isEmpty, "judgement word(s) \(offending.sorted()) in: \(text)")
        }
        for text in texts {
            #expect(!text.lowercased().contains("clipping detected"), "a diagnosis, not a count, in: \(text)")
        }
    }

    /// No stable code, wire key, framework name or domain case name reaches the screen.
    @Test func noSignalLevelTextLeaksAnInternalIdentifier() {
        let internals = [
            "unavailable", "cancelled", "SignalLevelMetricsOutcome", "SignalLevelMetricsAccumulator",
            "AVFoundation", "vDSP", "OSStatus", "NSError", "schemaVersion", "peakSample(", "sampleCount",
        ]
        var texts = allStateText(.loading) + allStateText(.absent)
            + allStateText(.failed(message: "The signal level metrics for this file could not be produced."))
        texts += allRowText(monoMetrics) + allRowText(stereoMetrics)
        for text in texts {
            #expect(!text.contains("_"), "underscored identifier surfaced: \(text)")
            for identifier in internals {
                #expect(
                    !text.lowercased().contains(identifier.lowercased()),
                    "internal identifier “\(identifier)” surfaced in: \(text)"
                )
            }
        }
    }

    /// `-∞`/`-inf` must never reach the screen, whatever channel count or silence pattern produced it.
    @Test func noSignalLevelTextShowsAMathematicalInfinity() {
        for metrics in [monoMetrics, stereoMetrics, zeroFrameMetrics, silentMetrics] {
            for text in allRowText(metrics) {
                #expect(!text.lowercased().contains("inf"), "infinity leaked in: \(text)")
                #expect(!text.contains("∞"), "infinity leaked in: \(text)")
            }
        }
    }

    // MARK: - The composition root joins the two feature vocabularies

    /// The one place `FeatureImport`'s state becomes `FeatureAnalysis`'s presentation — mirrors the
    /// identical test already pinned for the waveform and the spectrogram.
    @Test func everyFlowStateMapsToItsPresentation() {
        let metrics = monoMetrics
        #expect(RootView.signalLevelMetricsPresentation(for: .loading) == .loading)
        #expect(RootView.signalLevelMetricsPresentation(for: .available(metrics)) == .metrics(metrics))
        #expect(RootView.signalLevelMetricsPresentation(for: .unavailable) == .absent)
        #expect(RootView.signalLevelMetricsPresentation(for: .failed(message: "nope")) == .failed(message: "nope"))
    }

    /// A reading that failed must not be shown as one the file could not offer, and vice versa.
    @Test func afailureAndAnAbsenceAreNeverPresentedAsTheSameThing() {
        let failed = RootView.signalLevelMetricsPresentation(
            for: .failed(message: "The signal level metrics for this file could not be produced.")
        )
        #expect(failed != .absent)
        #expect(SignalLevelMetricsCopy.text(for: failed)?.headline != SignalLevelMetricsCopy.text(for: .absent)?.headline)
    }
}
