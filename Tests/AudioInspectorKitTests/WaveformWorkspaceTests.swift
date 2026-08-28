import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

// R5's subject: **the amplitude drawing, given room — and the paired lane's words, given somewhere to
// be.**
//
// The drawing itself cannot be asserted, so what is asserted is what decides it: the sizing values, the
// states, and the *structure* of the surface that renders them. The last of those is the point of this
// suite — the overlap this slice closes was invisible to every test the surface had, because no test
// looked at how the lane was built.

@Suite("Feature — the waveform workspace")
struct WaveformWorkspaceTests {

    // MARK: - Fixtures

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureAnalysis")
    }

    private func source(_ name: String) throws -> String {
        try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
    }

    /// The file's **code**, with documentation and comments removed.
    ///
    /// A sweep for words a surface may not use has to read what it does, not what it says about itself:
    /// the comments here deliberately name every capability the section refuses, so sweeping them would
    /// find every one of them.
    private func code(_ name: String) throws -> String {
        try source(name)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
            .joined(separator: "\n")
    }

    private func bucket(_ minimum: Float, _ maximum: Float) throws -> WaveformBucket {
        try #require(WaveformBucket(minimum: minimum, maximum: maximum))
    }

    private func envelope(buckets count: Int = 64, channels: Int = 2) throws -> WaveformEnvelope {
        let buckets = try (0 ..< count).map { index -> WaveformBucket in
            let amplitude = Float(index % 8) / 8
            return try bucket(-amplitude, amplitude)
        }
        return try #require(
            WaveformEnvelope(buckets: buckets, frameCount: count * 512, channelCount: channels)
        )
    }

    /// Two lanes on one axis, the second file ending before the first — the case whose remainder the
    /// out-of-range sentence exists for.
    private func pairedWithShorterSecond() throws -> PairedWaveformPresentation {
        let first = try #require(PCMStreamDescription(sampleRate: 48_000, channelCount: 2, frameCount: 480_000))
        let second = try #require(PCMStreamDescription(sampleRate: 48_000, channelCount: 2, frameCount: 240_000))
        return PairedWaveformPresentation(
            axis: try #require(PairedWaveformAxis(first: first, second: second)),
            first: .envelope(try envelope()),
            second: .envelope(try envelope())
        )
    }

    // MARK: - 1.1 — the plot is sized by a value with a reason

    /// The report page's strip is unchanged, so the transitional surface looks exactly as it did.
    @Test("the report page keeps the fixed strip it has always had")
    func reportPageKeepsItsStrip() {
        #expect(WaveformPlotSizing.reportPage == .fixed(96))
        #expect(WaveformPlotSizing.reportPage.minimum == WaveformPlotSizing.reportPage.maximum)
    }

    /// The workspace's sizings **flex**: a minimum that is not the maximum is what makes the drawing
    /// grow with the window, and is the whole difference from the strip it replaces.
    @Test("the workspace sizings grow with the window")
    func workspaceSizingsFlex() {
        for sizing in [WaveformPlotSizing.workspaceSingle, .workspaceLane] {
            #expect(sizing.minimum < sizing.maximum, "a workspace sizing that cannot grow")
            #expect(sizing.minimum > 0)
        }
        #expect(WaveformPlotSizing.workspaceSingle.minimum > WaveformPlotSizing.reportPage.minimum,
                "the workspace gives the drawing no more room than the page it replaces")
    }

    /// **Budgeted, not chosen by eye.** The window's minimum is 720 × 480; `design.md` §4 accounts for
    /// the navigation, the dividers, the action bar and the padding, leaving about 334 pt. A single plot
    /// plus its prose fits, and two lanes plus two sets of prose and the shared-extent line fit too.
    @Test("both sizings fit inside the smallest supported window")
    func sizingsFitTheSmallestWindow() {
        let contentHeight: CGFloat = 334
        let singleProse: CGFloat = 34
        #expect(WaveformPlotSizing.workspaceSingle.minimum + singleProse <= contentHeight)

        let perLaneProse: CGFloat = 58
        let sharedExtentLine: CGFloat = 16
        let paired = 2 * (WaveformPlotSizing.workspaceLane.minimum + perLaneProse) + sharedExtentLine
        #expect(paired <= contentHeight, "two lanes do not fit at the window's minimum height")
    }

    /// A maximum exists, and is not decoration: an envelope's vertical information is bounded by the
    /// amplitude scale rather than by pixels.
    @Test("neither sizing is unbounded")
    func neitherSizingIsUnbounded() {
        for sizing in [WaveformPlotSizing.workspaceSingle, .workspaceLane, .reportPage] {
            #expect(sizing.maximum.isFinite)
            #expect(sizing.maximum < 1_000)
        }
    }

    // MARK: - 5.1 — the overlap's structural guard

    /// **The property the old code violated, and no test could see.**
    ///
    /// The lane used to place `WaveformSection` — a composite of a drawing *and* two lines of prose —
    /// inside a `GeometryReader` frozen at the drawing's own height. `GeometryReader` does not clip, so
    /// the prose was drawn over the next lane. Nothing here can regress to that shape: a `…Section` in
    /// this codebase is a composite, and none may be constructed inside a measured area.
    @Test("no composite section is built inside a measured area")
    func noCompositeSectionInsideAMeasuredArea() throws {
        let code = try code("PairedVisualsView.swift")
        for block in geometryReaderBlocks(in: code) {
            #expect(
                !block.contains("Section("),
                "a composite section is constructed inside a GeometryReader:\n\(block)"
            )
            #expect(
                !block.contains("Text("),
                "text is laid out inside a GeometryReader:\n\(block)"
            )
        }
    }

    /// The paired lane renders **its own** prose, from the copy owner that already produced it for that
    /// lane. It used to compute those strings and render none of them, delegating to the section nested
    /// inside — one sentence with two owners, and the owner that drew it had no room.
    @Test("the paired lane renders every part of its own text")
    func theLaneRendersItsOwnText() throws {
        let lane = try pairedWaveformLaneSource()
        for part in ["text.attribution", "text.headline", "text.detail", "text.outOfRange"] {
            #expect(lane.contains(part), "the lane does not render \(part)")
        }
        // And it builds no single-file section to render them for it.
        #expect(!lane.contains("WaveformSection("), "the lane still builds the composite section")
    }

    /// The words are laid out by the layout, at whatever size they need — never inside a region reserved
    /// for a picture.
    @Test("the lane's words are allowed the height they need")
    func theLanesWordsAreAllowedTheirHeight() throws {
        let lane = try pairedWaveformLaneSource()
        let textLines = lane.components(separatedBy: .newlines).filter { $0.contains("Text(text.") }
        #expect(!textLines.isEmpty)
        #expect(
            lane.components(separatedBy: "fixedSize(horizontal: false, vertical: true)").count - 1 >= 3,
            "a lane sentence may be truncated rather than wrapped"
        )
    }

    // MARK: - 5.3 — room buys no powers

    /// Room is not a power (ADR-0026 §9). Swept over the sources this slice writes and edits, rather
    /// than trusted to the diff.
    @Test("the workspace introduces no interaction")
    func theWorkspaceIntroducesNoInteraction() throws {
        let forbidden = [
            "onTapGesture", "onHover", "DragGesture", "MagnificationGesture", "MagnifyGesture",
            "RotateGesture", "onLongPressGesture", "gesture(", "simultaneousGesture", "highPriorityGesture",
            "ScrollViewReader", "scrollTo", "draggable", "dropDestination", ".selection", "Slider",
            "playhead", "scrub", "cursor", "zoom", "transport", "AVPlayer", "AVAudioPlayer",
            "alignment(to:", "overlayWaveform", "differenceWaveform", "correlation", "similarity",
            "normalise", "normalize", "gainMatch",
        ]
        for file in ["ReportWaveformView.swift", "PairedVisualsView.swift", "WaveformView.swift"] {
            let body = try code(file)
            for word in forbidden {
                #expect(!body.contains(word), "\(file) reaches for \(word)")
            }
        }
    }

    /// The drawing stays untouchable, whatever height it is given.
    @Test("the drawing still takes no hit")
    func theDrawingStillTakesNoHit() throws {
        #expect(try source("WaveformView.swift").contains("allowsHitTesting(false)"))
    }

    /// **This slice computes nothing.** The workspace is built from a presentation, so no decoder, no
    /// read and no accumulator can be reached from it.
    @Test("the workspace starts no work of its own")
    func theWorkspaceStartsNoWork() throws {
        let forbidden = ["AVFoundation", "AudioInspectorMedia", "AudioInspectorAnalysis", "Process",
                         "Accumulator", "Decoder", "decode", "Task {", "async ", "await "]
        let body = try code("ReportWaveformView.swift")
        for word in forbidden {
            #expect(!body.contains(word), "the workspace reaches for \(word)")
        }
    }

    /// The arithmetic this slice must not touch is the arithmetic it does not mention.
    @Test("the workspace decides no geometry of its own")
    func theWorkspaceDecidesNoGeometry() throws {
        let body = try code("ReportWaveformView.swift")
        for word in ["WaveformGeometry", "PairedWaveformAxis(", "WaveformBucket", "fraction", "sharedSeconds"] {
            #expect(!body.contains(word), "the workspace reaches into \(word)")
        }
    }

    // MARK: - 5.2 — the semantics the drawing already had

    /// A shorter file's lane is drawn across its own share of the axis and **stops there**; the rest
    /// carries no drawn value at all. The share is `PairedWaveformAxis`', untouched by this slice.
    @Test("a shorter file's lane occupies only its own share")
    func aShorterLaneOccupiesItsOwnShare() throws {
        let paired = try pairedWithShorterSecond()
        let axis = try #require(paired.axis)
        #expect(try #require(axis.first).fraction == 1)
        #expect(try #require(axis.second).fraction == 0.5)
        #expect(try #require(axis.second).remainderFraction == 0.5)
    }

    /// **The remainder is never silence.** Nothing is drawn in it — the lane renders no view at all for
    /// a lane with no envelope, and the plot is clipped to the fraction — and the sentence saying so is
    /// the one `PairedVisualsCopy` already owns.
    @Test("the remainder is stated in words and drawn as nothing")
    func theRemainderIsWordsNotSilence() throws {
        let paired = try pairedWithShorterSecond()
        let text = PairedVisualsCopy.waveform(
            paired.second, for: .second,
            beyondItsAudio: (paired.axis?.second?.remainderFraction ?? 0) > 0
        )
        let outOfRange = try #require(text.outOfRange)
        #expect(outOfRange == PairedVisualsCopy.outsideAudio)
        for word in ["silence", "silent", "empty", "no signal", "zero", "baseline", "floor"] {
            #expect(!outOfRange.lowercased().contains(word), "the remainder reads as \(word)")
        }
        // And the lane's plot is the only thing the fraction is applied to.
        let lane = try pairedWaveformLaneSource()
        #expect(lane.contains("plot(lane, fraction:"))
    }

    /// **Two lanes, never one plot.** An overlay would put two files in one picture and invite a
    /// comparison neither drawing can support.
    @Test("the two lanes are separate, never overlaid")
    func theTwoLanesAreSeparate() throws {
        let body = try code("PairedVisualsView.swift")
        let section = try pairedWaveformSectionSource()
        #expect(section.contains("lane(.first,"))
        #expect(section.contains("lane(.second,"))
        // Neither lane is drawn into the other's area: there is no stack holding both.
        #expect(!section.contains("ZStack"), "the two waveform lanes share a stack")
        #expect(!body.contains("blendMode"), "a lane is composited onto another")
    }

    // MARK: - 5.4 — states, and one element per drawing

    /// Loading, absent and failed are three different answers and read as three different sentences —
    /// and none of them is an empty drawing.
    @Test("the three absences are distinguishable and none is a picture")
    func theThreeAbsencesAreDistinguishable() throws {
        let states: [WaveformPresentation] = [
            .loading, .absent, .failed(message: "The drawing could not be produced."),
        ]
        let headlines = states.map { WaveformCopy.text(for: $0).headline }
        #expect(Set(headlines.compactMap { $0 }).count == 3, "two states share a sentence")
        for state in states {
            let text = WaveformCopy.text(for: state)
            #expect(text.headline != nil, "a state with no sentence to read")
            #expect(!text.accessibilityLabel.isEmpty)
        }
    }

    /// A file with real audio and a file with none are different answers, and neither is an absence.
    @Test("an envelope with no buckets is a statement, not an absence")
    func anEmptyEnvelopeIsAStatement() throws {
        let empty = try #require(WaveformEnvelope(buckets: [], frameCount: 0, channelCount: 1))
        let text = WaveformCopy.text(for: .envelope(empty))
        #expect(text.headline != nil, "a file with no frames draws a bare centre line and says nothing")
        #expect(text.headline != WaveformCopy.text(for: .absent).headline)
    }

    /// **One element per drawing, never one per bucket.** 2048 shapes announced in sequence would be
    /// worse than silence.
    @Test("each drawing is one accessibility element")
    func eachDrawingIsOneElement() throws {
        for file in ["ReportWaveformView.swift", "PairedVisualsView.swift", "WaveformView.swift"] {
            let body = try code(file)
            #expect(body.contains("accessibilityElement(children: .ignore)"), "\(file) loses the contract")
            #expect(!body.contains("accessibilityLabel(bucket"), "\(file) announces a bucket")
        }
        // The paired lane names which file it belongs to.
        let paired = try pairedWithShorterSecond()
        let text = PairedVisualsCopy.waveform(paired.first, for: .first, beyondItsAudio: false)
        #expect(text.accessibilityLabel.contains(ComparisonCopy.firstFile))
    }

    // MARK: - Source helpers

    /// Every `GeometryReader { … }` block in a file, by brace depth.
    private func geometryReaderBlocks(in code: String) -> [String] {
        var blocks: [String] = []
        var search = code[...]
        while let start = search.range(of: "GeometryReader") {
            guard let open = search[start.upperBound...].firstIndex(of: "{") else { break }
            var depth = 0
            var end = open
            for index in search[open...].indices {
                let character = search[index]
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { end = index; break }
                }
            }
            blocks.append(String(search[open ... end]))
            search = search[search.index(after: end)...]
        }
        return blocks
    }

    private func pairedWaveformSectionSource() throws -> String {
        let body = try code("PairedVisualsView.swift")
        let start = try #require(body.range(of: "struct PairedWaveformSection"))
        let end = try #require(body.range(of: "struct PairedSpectrogramSection"))
        return String(body[start.lowerBound ..< end.lowerBound])
    }

    private func pairedWaveformLaneSource() throws -> String {
        let section = try pairedWaveformSectionSource()
        let start = try #require(section.range(of: "private func lane("))
        return String(section[start.lowerBound...])
    }
}
