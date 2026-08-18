import Testing

import AudioInspectorDomain
@testable import FeatureAnalysis

/// **Does the comparison cover every technical property, or only the ones it happened to be born with?**
///
/// The approved spec is not satisfied by a fixed number of properties. It says: *"For every technical
/// property both reports carry, the system SHALL state exactly one of three outcomes … The set SHALL be
/// exhaustive, so no property is left without an outcome."*
///
/// `FileComparison` was written when `TechnicalProperties` held eight properties. A ninth —
/// `averageFileBitrate` — arrived two days later, and nothing here noticed: the report shows it, the
/// export carries it, and the comparison silently drops it. The surface's own
/// `rows(for:)` even truncates to the outcome count, so the omission produces no warning, no gap and no
/// failing test.
///
/// This suite exists so that cannot happen again. It asserts **coverage as a property of the types**
/// rather than as a number to be updated by hand, so a tenth property added tomorrow fails here on the
/// day it is added rather than being discovered by a reader wondering where their row went.
@MainActor
@Suite("Comparison — every technical property is covered")
struct ComparisonPropertyCoverageTests {

    private func reference(_ name: String) -> AudioFileReference {
        AudioFileReference(
            displayName: name,
            fileExtension: "wav",
            sizeBytes: 1_024,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
        )
    }

    private func report(_ name: String, _ properties: TechnicalProperties) -> InspectionReport {
        InspectionReport(file: reference(name), properties: properties, warnings: [], status: .completed)
    }

    /// Every property available, so nothing is `incomparable` for a reason unrelated to coverage.
    private var base: TechnicalProperties {
        TechnicalProperties(
            container: .available("wav"),
            duration: .available(180.0),
            sampleRate: .available(44_100),
            channelCount: .available(2),
            bitDepth: .available(16),
            codec: .available("lpcm"),
            declaredBitrate: .available(1_411_200),
            estimatedBitrate: .available(1_411_000),
            averageFileBitrate: .available(1_410_500)
        )
    }

    private func comparison(_ second: TechnicalProperties) -> FileComparison {
        FileComparison(first: report("a.wav", base), second: report("b.wav", second))
    }

    // MARK: - Coverage, asserted structurally

    /// **The structural claim**: `FileComparison` carries one `PropertyComparison` per stored property of
    /// `TechnicalProperties`.
    ///
    /// Swift offers no compile-time reflection over stored properties, so this is a **runtime** assertion
    /// over `Mirror`, which does enumerate them for a struct. That is the closest this language gets to
    /// making the coupling checkable at all; the alternative — a hand-written number — is the very thing
    /// that failed. Matching on the type's name rather than on a protocol is deliberate:
    /// `PropertyComparison` is generic over its `Value`, so there is no single existential to test against
    /// without adding one to the domain purely for a test's benefit.
    @Test("the comparison holds one outcome per technical property")
    func everyTechnicalPropertyHasAnOutcome() {
        let properties = Mirror(reflecting: TechnicalProperties()).children.count
        let outcomes = Mirror(reflecting: comparison(base)).children.filter {
            "\(type(of: $0.value))".hasPrefix("PropertyComparison<")
        }.count

        #expect(
            outcomes == properties,
            "TechnicalProperties has \(properties) properties but FileComparison compares \(outcomes)"
        )
    }

    /// **The observable claim**, which is what a reader actually notices: the comparison surface shows a
    /// row for every property the single-file report shows.
    ///
    /// It is the counterpart to the structural test rather than a duplicate of it: this one would still
    /// fail if the domain gained an outcome that the formatter forgot to render, which `Mirror` over the
    /// domain type cannot see.
    @Test("the surface shows a row for every property the report itself shows")
    func everyReportedPropertyHasARow() {
        let displayed = ReportPropertyFormatter.displays(for: base).map(\.name)
        let rows = ComparisonFormatter.rows(for: comparison(base)).map(\.name)

        #expect(rows == displayed, "the comparison rows are not the report's own properties")
    }

    /// **Alignment, proof against any permutation.**
    ///
    /// The formatter zips two lists built in different places: the report's property displays, and a
    /// hand-written list of outcomes. Position is the only thing binding them, so a reordering of either
    /// silently attaches one property's outcome to another's row.
    ///
    /// A negative control showed the existing tests could not see that: swapping `container` and
    /// `duration` in the outcome list broke nothing, because in every fixture they were both *the same*
    /// and two identical outcomes are indistinguishable however they are shuffled.
    ///
    /// So this fixture gives **every one of the nine properties a distinct outcome** — one same, one
    /// different, and seven *not comparable* whose reasons differ because the state pairs behind them
    /// differ. Any permutation of the outcome list therefore changes at least one row, and the mapping
    /// below is asserted in full rather than sampled.
    @Test("each row carries its own property's outcome, under a fixture where all nine differ")
    func everyRowCarriesItsOwnOutcomeUnderDistinctOutcomes() {
        let first = TechnicalProperties(
            container: .available("wav"),
            duration: .available(180.0),
            sampleRate: .available(44_100),
            channelCount: .unavailable(reason: "no channel count"),
            bitDepth: .available(16),
            codec: .available("lpcm"),
            declaredBitrate: .available(1_411_200),
            estimatedBitrate: .unavailable(reason: "first has no estimate"),
            averageFileBitrate: .uncertain(value: 1_410_500, reason: "calculated from size and duration")
        )
        let second = TechnicalProperties(
            container: .available("wav"),
            duration: .available(240.0),
            sampleRate: .unavailable(reason: "second has no rate"),
            channelCount: .available(2),
            bitDepth: .unsupported(reason: "lossy codec"),
            codec: .uncertain(value: "lpcm", reason: "inferred"),
            declaredBitrate: .failed(PropertyFailure(code: .propertyReadError, message: "read error")),
            estimatedBitrate: .unavailable(reason: "second has no estimate"),
            averageFileBitrate: .available(1_410_500)
        )
        let rows = ComparisonFormatter.rows(
            for: FileComparison(first: report("a.wav", first), second: report("b.wav", second))
        )

        // The fixture only works if the outcomes really are distinguishable; assert that first, so a
        // future change to the copy cannot quietly turn this into a weaker test than it reads as.
        let texts = rows.map(\.outcome.text)
        #expect(Set(texts).count == rows.count, "two properties share an outcome, so a swap would hide")

        #expect(rows.map(\.name) == [
            "Container", "Duration", "Sample rate", "Channel count",
            "Bit depth", "Codec", "Declared bitrate", "Estimated bitrate", "Average file bitrate",
        ])
        #expect(texts == [
            "Same",
            "Different",
            "Not comparable — the second file does not carry this property.",
            "Not comparable — the first file does not carry this property.",
            "Not comparable — the second file's format cannot express it.",
            "Not comparable — the second file's value was read but is not reliable.",
            "Not comparable — the second file's value could not be read.",
            "Not comparable — neither file carries this property.",
            "Not comparable — the first file's value was read but is not reliable.",
        ])
    }

    // MARK: - The ninth property behaves like the other eight

    @Test("an average file bitrate that agrees reports the same")
    func averageFileBitrateSameIsReported() throws {
        let rows = ComparisonFormatter.rows(for: comparison(base))
        let row = try #require(rows.first { $0.name == "Average file bitrate" }, "no average file bitrate row")
        #expect(row.outcome == .same)
    }

    @Test("an average file bitrate that disagrees reports different")
    func averageFileBitrateDifferentIsReported() throws {
        var second = base
        second.averageFileBitrate = .available(320_000)
        let row = try #require(
            ComparisonFormatter.rows(for: comparison(second)).first { $0.name == "Average file bitrate" }
        )
        #expect(row.outcome == .different)
    }

    /// Absent on one side is *not comparable* — the same rule every other property follows, and the state
    /// `averageFileBitrate` is in for most real files.
    @Test("an average file bitrate missing on one side is not comparable")
    func averageFileBitrateUnavailableIsNotComparable() throws {
        var second = base
        second.averageFileBitrate = .unavailable(reason: "not exposed by this container")
        let row = try #require(
            ComparisonFormatter.rows(for: comparison(second)).first { $0.name == "Average file bitrate" }
        )
        if case .notComparable = row.outcome {} else {
            Issue.record("expected not comparable, got \(row.outcome)")
        }
    }

    /// **An estimate is never a comparable fact**, and `averageFileBitrate` is the property most often in
    /// that state: `AVFoundationAudioFilePropertyReader` can only ever return it as `uncertain`. If this
    /// reported *same* for two matching estimates it would present an unreliable reading as comparable,
    /// which the spec forbids for every property.
    @Test("two uncertain average file bitrates are not comparable even when they match")
    func averageFileBitrateUncertainIsNotComparable() throws {
        var first = base
        first.averageFileBitrate = .uncertain(value: 1_410_500, reason: "calculated from size and duration")
        var second = base
        second.averageFileBitrate = .uncertain(value: 1_410_500, reason: "calculated from size and duration")
        let result = FileComparison(first: report("a.wav", first), second: report("b.wav", second))

        let row = try #require(
            ComparisonFormatter.rows(for: result).first { $0.name == "Average file bitrate" }
        )
        if case .notComparable = row.outcome {} else {
            Issue.record("an uncertain reading was presented as comparable: \(row.outcome)")
        }
    }

    // MARK: - Nothing else moved

    /// The eight properties that were already compared keep the exact outcomes they had. Adding the ninth
    /// is additive, and this is what says so.
    @Test("the eight pre-existing outcomes are unchanged by the ninth arriving")
    func thePreExistingOutcomesAreUnchanged() throws {
        var second = base
        second.sampleRate = .available(48_000)
        second.bitDepth = .unsupported(reason: "lossy")
        second.averageFileBitrate = .available(320_000)
        let rows = ComparisonFormatter.rows(for: comparison(second))

        func outcome(_ name: String) throws -> ComparisonOutcomeDisplay {
            try #require(rows.first { $0.name == name }, "no row named \(name)").outcome
        }

        #expect(try outcome("Container") == .same)
        #expect(try outcome("Duration") == .same)
        #expect(try outcome("Sample rate") == .different)
        #expect(try outcome("Channel count") == .same)
        if case .notComparable = try outcome("Bit depth") {} else {
            Issue.record("bit depth should not be comparable")
        }
        #expect(try outcome("Codec") == .same)
        #expect(try outcome("Declared bitrate") == .same)
        #expect(try outcome("Estimated bitrate") == .same)
        // And the newcomer, beside them.
        #expect(try outcome("Average file bitrate") == .different)
    }

    /// **Symmetry**: which file is A and which is B changes each row's two values and never the outcome.
    @Test("the ninth property's outcome does not depend on which side it is on")
    func averageFileBitrateIsSymmetric() throws {
        var other = base
        other.averageFileBitrate = .available(320_000)

        let forward = FileComparison(first: report("a.wav", base), second: report("b.wav", other))
        let backward = FileComparison(first: report("b.wav", other), second: report("a.wav", base))

        func outcome(_ result: FileComparison) throws -> ComparisonOutcomeDisplay {
            try #require(
                ComparisonFormatter.rows(for: result).first { $0.name == "Average file bitrate" }
            ).outcome
        }
        #expect(try outcome(forward) == (try outcome(backward)))
        #expect(try outcome(forward) == .different)
    }
}
