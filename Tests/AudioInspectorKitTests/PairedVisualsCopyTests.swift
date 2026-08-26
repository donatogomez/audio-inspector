import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// Group 7's subject: **what a paired drawing is allowed to say.**
//
// Every string this surface can render, in every state, on both sides — collected once here so the sweep
// covers the surface rather than the repository, and so a state added later has nowhere to hide.

@Suite("Presentation — what a paired drawing says")
struct PairedVisualsCopyTests {

    // MARK: - Fixtures

    private func envelope(buckets: Int, channels: Int = 2) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: (0 ..< buckets).map { _ in WaveformBucket(minimum: -0.5, maximum: 0.5)! },
            frameCount: buckets == 0 ? 0 : 2_048,
            channelCount: channels
        )!
    }

    private func model(columns: Int, channels: Int = 2) -> Spectrogram {
        columns == 0
            ? Spectrogram.empty(sampleRate: 44_100, channelCount: channels)!
            : Spectrogram(
                values: Array(repeating: Float(-30), count: columns * 2), columnCount: columns, bandCount: 2,
                sampleRate: 44_100, frameCount: 2_048, channelCount: channels
            )!
    }

    private var waveformLanes: [PairedWaveformLane] {
        [.envelope(envelope(buckets: 4)), .envelope(envelope(buckets: 0)), .absent, .failed(message: "The waveform for this file could not be produced.")]
    }

    private var spectrogramLanes: [PairedSpectrogramLane] {
        [.model(model(columns: 3)), .model(model(columns: 0)), .absent, .failed(message: "The spectrogram for this file could not be produced.")]
    }

    private let sides: [PairedWaveformAxis.Side] = [.first, .second]

    /// **Every string the paired surface can render.** Both sides, every lane state, both answers to
    /// *does this file reach the whole axis*, plus the axis lines and the attributions.
    private func everyRenderableString(channels: Int = 2) -> [String] {
        var strings: [String] = []
        for side in sides {
            strings.append(PairedVisualsCopy.attribution(side))
            for lane in [PairedWaveformLane.envelope(envelope(buckets: 4, channels: channels)),
                         .envelope(envelope(buckets: 0, channels: channels)), .absent,
                         .failed(message: "The waveform for this file could not be produced.")] {
                for beyond in [true, false] {
                    let text = PairedVisualsCopy.waveform(lane, for: side, beyondItsAudio: beyond)
                    strings.append(contentsOf: [text.attribution, text.accessibilityLabel])
                    strings.append(contentsOf: [text.headline, text.detail, text.outOfRange].compactMap { $0 })
                }
            }
            for lane in [PairedSpectrogramLane.model(model(columns: 3, channels: channels)),
                         .model(model(columns: 0, channels: channels)), .absent,
                         .failed(message: "The spectrogram for this file could not be produced.")] {
                for above in [true, false] {
                    let text = PairedVisualsCopy.spectrogram(lane, for: side, aboveItsNyquist: above)
                    strings.append(contentsOf: [text.attribution, text.accessibilityLabel])
                    strings.append(contentsOf: [text.headline, text.detail, text.outOfRange].compactMap { $0 })
                }
            }
        }
        strings.append(PairedVisualsCopy.timeAxis(212.5))
        strings.append(PairedVisualsCopy.frequencyAxis(48_000))
        return strings
    }

    // MARK: - 7.5 — attribution is position, and only position

    @Test("the two files are named by position, and by nothing else")
    func attributionIsPositional() {
        #expect(PairedVisualsCopy.attribution(.first) == ComparisonCopy.firstFile)
        #expect(PairedVisualsCopy.attribution(.second) == ComparisonCopy.secondFile)
        #expect(PairedVisualsCopy.attribution(.first) != PairedVisualsCopy.attribution(.second))
    }

    /// **The words follow the position, never the content.** The same lane on the other side is named
    /// the other way round, and nothing else about what it says changes.
    @Test("swapping the sides swaps only the attribution")
    func languageFollowsPosition() {
        for lane in waveformLanes {
            let asFirst = PairedVisualsCopy.waveform(lane, for: .first, beyondItsAudio: false)
            let asSecond = PairedVisualsCopy.waveform(lane, for: .second, beyondItsAudio: false)
            #expect(asFirst.attribution == ComparisonCopy.firstFile)
            #expect(asSecond.attribution == ComparisonCopy.secondFile)
            #expect(asFirst.headline == asSecond.headline)
            #expect(asFirst.detail == asSecond.detail)
            #expect(asFirst.accessibilityLabel != asSecond.accessibilityLabel)
        }
        for lane in spectrogramLanes {
            let asFirst = PairedVisualsCopy.spectrogram(lane, for: .first, aboveItsNyquist: false)
            let asSecond = PairedVisualsCopy.spectrogram(lane, for: .second, aboveItsNyquist: false)
            #expect(asFirst.headline == asSecond.headline)
            #expect(asFirst.attribution != asSecond.attribution)
        }
    }

    // MARK: - 7.1 / 7.2 — absent, failed and too-short are three statements

    @Test("an absent drawing says so, on either side and for either artefact")
    func absenceIsSaidInWords() {
        for side in sides {
            let waveform = PairedVisualsCopy.waveform(.absent, for: side, beyondItsAudio: false)
            let spectrogram = PairedVisualsCopy.spectrogram(.absent, for: side, aboveItsNyquist: false)
            #expect(waveform.headline == "No waveform for this file.")
            #expect(spectrogram.headline == "No spectrogram for this file.")
            // The two artefacts are named apart: one sentence for both would lose which is missing.
            #expect(waveform.headline != spectrogram.headline)
        }
    }

    /// A failure keeps its own neutral sentence, and stays distinct from an absence.
    @Test("a failed drawing keeps its message, and never reads as an absence")
    func failureIsNotAbsence() {
        for side in sides {
            let waveform = PairedVisualsCopy.waveform(
                .failed(message: "The waveform for this file could not be produced."),
                for: side, beyondItsAudio: false
            )
            let spectrogram = PairedVisualsCopy.spectrogram(
                .failed(message: "The spectrogram for this file could not be produced."),
                for: side, aboveItsNyquist: false
            )
            #expect(waveform.headline == "The waveform for this file could not be produced.")
            #expect(spectrogram.headline == "The spectrogram for this file could not be produced.")
            #expect(waveform != PairedVisualsCopy.waveform(.absent, for: side, beyondItsAudio: false))
            #expect(spectrogram != PairedVisualsCopy.spectrogram(.absent, for: side, aboveItsNyquist: false))
            // Neutral: no path, no framework, no stable code.
            for text in [waveform, spectrogram] {
                let all = [text.headline, text.detail].compactMap { $0 }.joined(separator: " ")
                #expect(!all.contains("/"), "a path reached the surface: \(all)")
                #expect(!all.lowercased().contains("avfoundation"))
                #expect(!all.lowercased().contains("nserror"))
            }
        }
    }

    /// **A model with no columns is too short to analyse, not missing.** The single-file sentence is
    /// reused rather than rewritten, and it is a third statement beside absent and failed.
    @Test("a model with no columns says it is too short, not that there is none")
    func tooShortIsItsOwnStatement() {
        let short = PairedVisualsCopy.spectrogram(.model(model(columns: 0)), for: .first, aboveItsNyquist: false)
        let absent = PairedVisualsCopy.spectrogram(.absent, for: .first, aboveItsNyquist: false)
        let failed = PairedVisualsCopy.spectrogram(
            .failed(message: "no"), for: .first, aboveItsNyquist: false
        )
        #expect(short.headline == "This file is too short to analyse as a spectrogram.")
        #expect(short != absent)
        #expect(short != failed)
        #expect(absent != failed)
    }

    // MARK: - 7.3 — two regions, two facts, two sentences

    @Test("the region past a file's audio is not silence, and says what it is")
    func pastTheAudio() {
        let text = PairedVisualsCopy.waveform(.envelope(envelope(buckets: 4)), for: .first, beyondItsAudio: true)
        #expect(text.outOfRange == "This file carries no audio beyond here.")
        #expect(text.accessibilityLabel.contains("This file carries no audio beyond here."))
        for forbidden in ["silence", "silent", "no signal", "empty", "missing"] {
            #expect(
                !(text.outOfRange ?? "").lowercased().contains(forbidden),
                "the time remainder was called \(forbidden)"
            )
        }
    }

    @Test("the region above a file's Nyquist is not the floor, and says what it is")
    func aboveTheNyquist() {
        let text = PairedVisualsCopy.spectrogram(.model(model(columns: 3)), for: .second, aboveItsNyquist: true)
        #expect(text.outOfRange == "This file cannot represent this range.")
        #expect(text.accessibilityLabel.contains("This file cannot represent this range."))
        for forbidden in ["floor", "no energy", "low energy", "silence", "truncated", "missing", "unsupported"] {
            #expect(
                !(text.outOfRange ?? "").lowercased().contains(forbidden),
                "the frequency remainder was called \(forbidden)"
            )
        }
    }

    /// **They are two sentences and can never be swapped.** A person has to tell them apart by reading
    /// them, which is what group 10's second manual check asks.
    @Test("the two out-of-range sentences are different, and each belongs to its own axis")
    func theTwoSentencesAreNotInterchangeable() {
        #expect(PairedVisualsCopy.outsideAudio != PairedVisualsCopy.outsideRepresentableRange)
        // The time remainder never speaks about frequency, and the frequency remainder never about time.
        let time = PairedVisualsCopy.waveform(.absent, for: .first, beyondItsAudio: true).outOfRange
        let frequency = PairedVisualsCopy.spectrogram(.absent, for: .first, aboveItsNyquist: true).outOfRange
        #expect(time == PairedVisualsCopy.outsideAudio)
        #expect(frequency == PairedVisualsCopy.outsideRepresentableRange)
        #expect(time != frequency)
        // And neither appears when the file reaches the whole of its axis.
        #expect(PairedVisualsCopy.waveform(.absent, for: .first, beyondItsAudio: false).outOfRange == nil)
        #expect(PairedVisualsCopy.spectrogram(.absent, for: .first, aboveItsNyquist: false).outOfRange == nil)
    }

    // MARK: - 7.4 — one side's absence says nothing about the other

    @Test("an absent side gets its own sentence and the present side keeps its own")
    func theSurvivingSideKeepsItsWords() {
        let absent = PairedVisualsCopy.waveform(.absent, for: .first, beyondItsAudio: false)
        let present = PairedVisualsCopy.waveform(.envelope(envelope(buckets: 4)), for: .second, beyondItsAudio: false)
        #expect(absent.headline == "No waveform for this file.")
        #expect(present.headline == nil, "the drawn side was given a sentence instead of a drawing")
        #expect(present.detail?.contains("Amplitude over the whole file") == true)
        // Neither mentions the other.
        #expect(!absent.accessibilityLabel.contains(ComparisonCopy.secondFile))
        #expect(!present.accessibilityLabel.contains(ComparisonCopy.firstFile))
    }

    // MARK: - 7.6 — the vocabulary sweep

    /// The terms ADR-0025 §12 forbids, plus the attribution words ADR-0017 refuses. Matched on word
    /// boundaries and case-insensitively, over **this surface's** strings and no others: a sweep of the
    /// repository would fail on the ADR that lists them and on the tests that check they are absent.
    static let forbidden = [
        "same", "identical", "different", "separated", "similar", "indistinguishable",
        "matching", "louder", "quieter", "high-frequency", "source", "original", "copy",
        "derived", "master", "remaster", "transcode", "upsample", "quality", "better", "worse",
        "confidence", "reference", "candidate",
    ]

    private func offendingTerms(in string: String) -> [String] {
        Self.forbidden.filter { term in
            string.range(of: "\\b\(term)\\b",
                         options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    @Test("no forbidden term appears in any string this surface can render, in any state")
    func theVocabularySweep() {
        let strings = everyRenderableString()
        #expect(strings.count > 40, "the sweep covered only \(strings.count) strings")
        for string in strings {
            let offences = offendingTerms(in: string)
            #expect(offences.isEmpty, "\"\(string)\" uses \(offences)")
        }
    }

    // MARK: - 7.8 — a differing channel count produces no statement

    /// Each lane says what its **own** file carries, as the single-file surface already does. Nothing
    /// compares the two counts, reconciles them, or remarks on the difference.
    @Test("two files with different channel counts produce no statement about the counts")
    func channelCountsAreNotCompared() {
        let mono = PairedVisualsCopy.waveform(.envelope(envelope(buckets: 4, channels: 1)), for: .first, beyondItsAudio: false)
        let stereo = PairedVisualsCopy.waveform(.envelope(envelope(buckets: 4, channels: 2)), for: .second, beyondItsAudio: false)
        #expect(mono.detail?.contains("1 channel") == true)
        #expect(stereo.detail?.contains("2 channels") == true)

        let remarks = [
            "not compared per channel", "channel counts", "channels differ", "1 and 2 channels",
            "channel mismatch", "differing channel",
        ]
        for string in everyRenderableString(channels: 1) + everyRenderableString(channels: 2) {
            for remark in remarks {
                #expect(
                    !string.lowercased().contains(remark),
                    "\"\(string)\" remarks on the channel counts"
                )
            }
        }
    }

    // MARK: - 7.7 — one element per drawing, and never one per bucket

    /// **The label's length does not depend on the model's size.** A drawing announced cell by cell would
    /// be far worse than silence, so the same sentence serves a 1-column grid and a 1 024-column one.
    @Test("a lane is announced as one element, whatever the drawing's resolution")
    func oneElementPerDrawing() {
        let small = PairedVisualsCopy.spectrogram(.model(model(columns: 1)), for: .first, aboveItsNyquist: false)
        let large = PairedVisualsCopy.spectrogram(.model(model(columns: 1_024)), for: .first, aboveItsNyquist: false)
        #expect(small.accessibilityLabel == large.accessibilityLabel)

        let fewBuckets = PairedVisualsCopy.waveform(.envelope(envelope(buckets: 2)), for: .first, beyondItsAudio: false)
        let manyBuckets = PairedVisualsCopy.waveform(.envelope(envelope(buckets: 2_048)), for: .first, beyondItsAudio: false)
        #expect(fewBuckets.accessibilityLabel == manyBuckets.accessibilityLabel)
    }

    /// Every lane names the file it belongs to and the artefact it is, in every state.
    @Test("every lane's label names its file and its artefact")
    func labelsNameFileAndArtefact() {
        for side in sides {
            let attribution = PairedVisualsCopy.attribution(side)
            for lane in waveformLanes {
                let label = PairedVisualsCopy.waveform(lane, for: side, beyondItsAudio: false).accessibilityLabel
                #expect(label.hasPrefix("\(attribution)."), "\(label)")
                #expect(label.contains(WaveformCopy.title), "\(label)")
            }
            for lane in spectrogramLanes {
                let label = PairedVisualsCopy.spectrogram(lane, for: side, aboveItsNyquist: false).accessibilityLabel
                #expect(label.hasPrefix("\(attribution)."), "\(label)")
                #expect(label.contains(SpectrogramCopy.title), "\(label)")
            }
        }
    }

    /// An absent or failed lane announces **that**, not a drawing that is not there.
    @Test("an absent or failed lane announces its state rather than a drawing")
    func absentLanesAnnounceTheirState() {
        let absent = PairedVisualsCopy.waveform(.absent, for: .first, beyondItsAudio: false)
        #expect(absent.accessibilityLabel.contains("No waveform for this file."))
        #expect(!absent.accessibilityLabel.contains("An amplitude envelope of the whole file"))

        let failed = PairedVisualsCopy.spectrogram(.failed(message: "It did not complete."), for: .second, aboveItsNyquist: false)
        #expect(failed.accessibilityLabel.contains("It did not complete."))
        #expect(!failed.accessibilityLabel.contains("A spectrogram of the whole file"))
    }

    // MARK: - Colour is never the only way

    /// The region above a file's Nyquist is drawn differently from the ramp's floor **and** said in
    /// words, so a reader who cannot separate the two colours still has the fact.
    @Test("the out-of-range region is available as text, not only as a colour")
    func notOnlyColour() {
        let text = PairedVisualsCopy.spectrogram(.model(model(columns: 3)), for: .first, aboveItsNyquist: true)
        #expect(text.outOfRange == PairedVisualsCopy.outsideRepresentableRange)
        #expect(text.accessibilityLabel.contains(PairedVisualsCopy.outsideRepresentableRange))
    }

    // MARK: - The shared extents are available as text

    @Test("the shared axes are stated in words")
    func extentsAreText() {
        let time = PairedVisualsCopy.timeAxis(212.5)
        let frequency = PairedVisualsCopy.frequencyAxis(48_000)
        #expect(time.contains("Time axis"))
        #expect(frequency.contains("Frequency axis"))
        #expect(frequency.contains(HumanFormat.frequency(48_000)))
        #expect(offendingTerms(in: time).isEmpty)
        #expect(offendingTerms(in: frequency).isEmpty)
    }
}
