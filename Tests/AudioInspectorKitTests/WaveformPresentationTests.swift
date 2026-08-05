import CoreGraphics
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureAnalysis
import FeatureImport

/// What the waveform surface must keep, asserted over the pure parts rather than over a rendering.
///
/// Nothing here is a snapshot. A snapshot of a `Canvas` would pin the exact pixels a particular SDK
/// produces and would fail on a font, a colour or a rounding change while proving nothing about the
/// guarantees that actually matter — which are arithmetic, and are asserted directly.
@Suite("Feature — waveform presentation")
struct WaveformPresentationTests {

    private func bucket(_ minimum: Float, _ maximum: Float) -> WaveformBucket {
        WaveformBucket(minimum: minimum, maximum: maximum)!
    }

    private func envelope(_ buckets: [WaveformBucket], frameCount: Int? = nil, channels: Int = 2) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: buckets,
            frameCount: frameCount ?? max(buckets.count, 0),
            channelCount: channels
        )!
    }

    private let area = CGSize(width: 400, height: 100)

    // MARK: - Amplitude maps to a position, and zero is the centre line

    @Test func silenceLandsExactlyOnTheCentreLine() throws {
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: 1))
        #expect(geometry.centreY == 50)
        #expect(geometry.y(forAmplitude: 0) == geometry.centreY)
    }

    /// Full scale reaches the edges, with `+1` at the top: a drawing that stopped short would understate
    /// amplitude, and one that inverted the axis would mirror the file.
    @Test func fullScaleReachesTheEdgesWithTheMaximumOnTop() throws {
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: 1))
        #expect(geometry.y(forAmplitude: 1) == 0)
        #expect(geometry.y(forAmplitude: -1) == area.height)
    }

    /// The picture must not favour one polarity: an asymmetric mapping would show a DC offset that the
    /// file does not have.
    @Test(arguments: [Float(0.25), 0.5, 0.75, 1])
    func oppositeAmplitudesAreEquallyFarFromTheCentre(amplitude: Float) throws {
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: 1))
        let above = geometry.centreY - geometry.y(forAmplitude: amplitude)
        let below = geometry.y(forAmplitude: -amplitude) - geometry.centreY
        #expect(above == below)
    }

    // MARK: - Values beyond the nominal range are limited by the drawing, not in the data

    /// The domain keeps a sample beyond `[-1, 1]` exactly as read. The drawing has edges, so it limits
    /// the coordinate — and only the coordinate.
    @Test(arguments: [Float(1.5), 2, 12.5, .greatestFiniteMagnitude])
    func anAmplitudeBeyondTheNominalRangeIsDrawnAtTheEdge(amplitude: Float) throws {
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: 1))
        #expect(geometry.y(forAmplitude: amplitude) == geometry.y(forAmplitude: 1))
        #expect(geometry.y(forAmplitude: -amplitude) == geometry.y(forAmplitude: -1))
    }

    @Test func clampingTheDrawingLeavesTheEnvelopeUntouched() throws {
        let outOfRange = bucket(-1.5, 1.5)
        let model = envelope([outOfRange])
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: 1))

        let bar = try #require(geometry.bar(forBucket: 0, of: outOfRange))
        #expect(bar.minY == 0 && bar.maxY == area.height) // drawn inside the area…

        #expect(model.buckets[0].minimum == -1.5) // …and the data still says what it said
        #expect(model.buckets[0].maximum == 1.5)
        #expect(model == envelope([bucket(-1.5, 1.5)]))
    }

    // MARK: - Buckets tile the width

    @Test func aSingleBucketOccupiesTheWholeWidth() throws {
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: 1))
        let band = try #require(geometry.horizontalBand(forBucket: 0))
        #expect(band.minX == 0)
        #expect(band.maxX == area.width)
    }

    /// No gap and no overlap at any count: one bucket's trailing edge is exactly the next one's leading
    /// edge, and the last one ends on the right edge. Computed from the index rather than accumulated,
    /// so rounding cannot drift across the full envelope.
    @Test(arguments: [1, 2, 3, 7, 401, 2_048])
    func theBandsCoverTheWidthWithoutAGapOrAnOverlap(bucketCount: Int) throws {
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: bucketCount))
        var previous: CGFloat = 0
        for index in 0 ..< bucketCount {
            let band = try #require(geometry.horizontalBand(forBucket: index))
            #expect(band.minX == previous)
            previous = band.maxX
        }
        #expect(previous == area.width)
    }

    /// More buckets than points is the ordinary case at the 2048 cap: the bands become sub-point and
    /// are drawn as they are. Nothing is decimated, merged or dropped, so the picture never depends on
    /// how wide the window happens to be.
    @Test func moreBucketsThanPointsStillProducesOneBarEach() throws {
        let buckets = (0 ..< 2_048).map { bucket(Float($0 % 3) * -0.25, Float($0 % 5) * 0.2) }
        let narrow = CGSize(width: 120, height: 40)
        let geometry = try #require(WaveformGeometry(size: narrow, bucketCount: buckets.count))

        let bars = geometry.bars(for: buckets)
        #expect(bars.count == 2_048)
        #expect(bars.allSatisfy { $0.width < 1 })
        #expect(bars.allSatisfy { $0.minX >= 0 && $0.maxX <= narrow.width })
    }

    @Test func theBarCountIsCappedByTheEnvelopeAndNeverExceedsTheProductionMaximum() throws {
        let buckets = (0 ..< WaveformBucketMapping.defaultMaximumBucketCount).map { _ in bucket(-0.5, 0.5) }
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: buckets.count))
        #expect(geometry.bars(for: buckets).count == WaveformBucketMapping.defaultMaximumBucketCount)
        #expect(geometry.bar(forBucket: buckets.count, of: bucket(0, 0)) == nil) // no bar past the end
    }

    // MARK: - Degenerate areas are ordinary, not errors

    /// A `Canvas` is laid out at zero before it settles, and a file with no frames has no buckets.
    /// Neither is a failure: the geometry declines, the view draws its centre line and stops.
    @Test(arguments: [
        CGSize(width: 0, height: 100), CGSize(width: 400, height: 0),
        CGSize(width: 0, height: 0), CGSize(width: 400, height: 0.5),
    ])
    func noGeometryExistsForAnAreaNothingFitsIn(size: CGSize) {
        #expect(WaveformGeometry(size: size, bucketCount: 1) == nil)
    }

    @Test func anEnvelopeWithNoBucketsProducesNoGeometry() {
        #expect(WaveformGeometry(size: area, bucketCount: 0) == nil)
    }

    /// A bucket of near-silence still draws, at the minimum height, centred where it actually is. Left
    /// to round away it would read as silence, which is a worse misstatement than a hairline.
    @Test func aVanishinglySmallBucketStillDrawsAndStaysInsideTheArea() throws {
        let geometry = try #require(WaveformGeometry(size: area, bucketCount: 3))
        for value in [Float(0), 0.000_01, 1, -1] {
            let bar = try #require(geometry.bar(forBucket: 0, of: bucket(value, value)))
            #expect(bar.height >= WaveformGeometry.minimumBarHeight)
            #expect(bar.minY >= 0 && bar.maxY <= area.height)
        }
    }

    // MARK: - The words, in every state

    private var everyState: [WaveformPresentation] {
        [
            .loading,
            .envelope(envelope([bucket(-0.8, 0.9)])),
            .envelope(WaveformEnvelope.empty(channelCount: 1)!),
            .absent,
            .failed(message: "The waveform for this file could not be produced."),
        ]
    }

    private func allText(_ presentation: WaveformPresentation) -> [String] {
        let text = WaveformCopy.text(for: presentation)
        return [text.headline, text.detail, text.accessibilityLabel].compactMap { $0 } + [WaveformCopy.title]
    }

    @Test func everyStateSaysSomethingRatherThanShowingNothing() {
        for presentation in everyState {
            let text = WaveformCopy.text(for: presentation)
            #expect(!text.accessibilityLabel.isEmpty)
            if case let .envelope(envelope) = presentation, !envelope.buckets.isEmpty {
                #expect(text.headline == nil) // the drawing is the content; the line beneath names it
                #expect(text.detail != nil)
            } else {
                #expect(text.headline != nil) // there is no drawing, so there are words instead
            }
        }
    }

    @Test func loadingSaysTheWaveformIsBeingPreparedAndNothingAboutTheFile() {
        let text = WaveformCopy.text(for: .loading)
        #expect(text.headline == "Preparing the waveform…")
        #expect(text.accessibilityLabel == "Waveform. Preparing the waveform.") // no ellipsis read aloud
    }

    @Test func adrawnEnvelopeIsDescribedAsWhatItIsAndAsCombinedRatherThanMixed() {
        let text = WaveformCopy.text(for: .envelope(envelope([bucket(-1, 1)], channels: 2)))
        #expect(text.detail == "Amplitude over the whole file, combined across 2 channels.")
        #expect(text.accessibilityLabel
            == "Waveform. An amplitude envelope of the whole file, combined across 2 channels.")
    }

    /// A valid file with zero frames. It is not an absence — the reading succeeded — so it is stated as
    /// the fact it is rather than reported as a waveform that could not be produced.
    @Test func anEnvelopeOfAFileWithNoFramesIsStatedAsSuchAndNotAsAnAbsence() {
        let text = WaveformCopy.text(for: .envelope(WaveformEnvelope.empty(channelCount: 2)!))
        #expect(text.headline == "This file contains no audio frames, so there is nothing to draw.")
        #expect(text.headline != WaveformCopy.text(for: .absent).headline)
    }

    @Test func anAbsentWaveformIsStatedInWordsAndClearsTheRestOfTheReport() {
        let text = WaveformCopy.text(for: .absent)
        #expect(text.headline == "No waveform for this file.")
        #expect(text.detail?.contains("Everything else in this report is unchanged") == true)
    }

    /// A failure is about producing the drawing. It must not read as a finding about the audio, and the
    /// report must be left standing.
    @Test func aFailureIsAboutTheDrawingAndNotAboutTheAudio() {
        let message = "The waveform for this file could not be produced."
        let text = WaveformCopy.text(for: .failed(message: message))
        #expect(text.headline == message)
        #expect(text.detail?.contains("not something read from the audio") == true)
        #expect(text.detail?.contains("Everything else in this report is unchanged") == true)
    }

    // MARK: - Nothing presented judges the audio, and nothing internal escapes

    /// Invariant #4 over the waveform surface, with the vocabulary the accepted requirement names
    /// explicitly — a drawing invites exactly these words, which is why they are swept for.
    @Test func noWaveformTextCharacterisesTheSignal() {
        let forbidden: Set<String> = [
            "loud", "quiet", "clipped", "clipping", "compressed", "dynamic", "healthy", "damaged",
            "good", "bad", "better", "worse", "quality", "poor", "distorted", "hot", "flat",
        ]
        for presentation in everyState {
            for text in allText(presentation) {
                let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
                let offending = words.intersection(forbidden)
                #expect(offending.isEmpty, "judgement word(s) \(offending.sorted()) in: \(text)")
            }
        }
    }

    /// No stable code, wire key, framework name or domain case name reaches the screen. The domain's
    /// own vocabulary is swept too: `unavailable` and `failed` are our identifiers, not the reader's.
    @Test func noWaveformTextLeaksAnInternalIdentifier() {
        let internals = [
            "unavailable", "available", "cancelled", "envelope(", "WaveformError", "AVAudioFile",
            "AVFoundation", "frameLength", "frameCapacity", "OSStatus", "NSError", "nonFiniteSample",
            "bucketCount", "schemaVersion",
        ]
        for presentation in everyState {
            for text in allText(presentation) {
                #expect(!text.contains("_"), "underscored identifier surfaced: \(text)")
                for identifier in internals {
                    #expect(
                        !text.lowercased().contains(identifier.lowercased()),
                        "internal identifier “\(identifier)” surfaced in: \(text)"
                    )
                }
            }
        }
    }

    /// The resolution cap is an implementation choice, not a promise: it is not exported, not persisted
    /// and not shown. A label that quoted it would turn it into a contract.
    @Test func noWaveformTextQuotesTheBucketCount() {
        let dense = envelope((0 ..< 2_048).map { _ in bucket(-0.5, 0.5) })
        for text in allText(.envelope(dense)) {
            #expect(!text.contains("2048") && !text.contains("2,048"))
        }
    }

    // MARK: - The waveform is one element, not one per bucket

    /// The label is composed from what the envelope *is*, never from what it contains, so a file with
    /// one bucket and a file at the cap are announced identically. That is the assertion behind "a
    /// single accessibility element": the announcement cannot grow with the drawing.
    @Test func theSpokenLabelDoesNotGrowWithTheNumberOfBuckets() {
        let one = envelope([bucket(-0.2, 0.4)], frameCount: 1)
        let many = envelope((0 ..< 2_048).map { index in bucket(Float(index % 7) * -0.1, Float(index % 11) * 0.09) })

        let first = WaveformCopy.text(for: .envelope(one)).accessibilityLabel
        let second = WaveformCopy.text(for: .envelope(many)).accessibilityLabel
        #expect(first == second)
    }

    /// …and it does say how many channels were folded in, because "the extremes across all channels" is
    /// not a complete statement without it.
    @Test(arguments: [(1, "1 channel"), (2, "2 channels"), (6, "6 channels")])
    func theSpokenLabelNamesHowManyChannelsWereCombined(channels: Int, expected: String) {
        let text = WaveformCopy.text(for: .envelope(envelope([bucket(-1, 1)], channels: channels)))
        #expect(text.accessibilityLabel.contains("combined across \(expected)"))
    }

    // MARK: - The composition root joins the two feature vocabularies

    /// The one place `FeatureImport`'s state becomes `FeatureAnalysis`'s presentation. Pinned because it
    /// is the only seam between two modules that cannot see each other, so nothing else would catch a
    /// state quietly mapping to the wrong words.
    @Test func everyFlowStateMapsToItsPresentation() {
        let envelope = envelope([bucket(-0.3, 0.6)])
        #expect(RootView.waveformPresentation(for: .loading) == .loading)
        #expect(RootView.waveformPresentation(for: .available(envelope)) == .envelope(envelope))
        #expect(RootView.waveformPresentation(for: .unavailable) == .absent)
        #expect(RootView.waveformPresentation(for: .failed(message: "nope")) == .failed(message: "nope"))
    }

    /// A waveform that failed must not be shown as one the file could not offer, and vice versa: the two
    /// carry different meanings and different words.
    @Test func afailureAndAnAbsenceAreNeverPresentedAsTheSameThing() {
        let failed = RootView.waveformPresentation(for: .failed(message: "The waveform for this file could not be produced."))
        #expect(failed != .absent)
        #expect(WaveformCopy.text(for: failed).headline != WaveformCopy.text(for: .absent).headline)
    }
}
