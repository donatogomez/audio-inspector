import Foundation
import Testing

@testable import AudioInspectorDomain

// `FileComparison` — the pure comparison of two reports. Domain only: no flow, no surface, no second
// file being chosen, no export. Group 4 does not exist yet and nothing here anticipates it.

private func reference(_ name: String) -> AudioFileReference {
    AudioFileReference(
        displayName: name,
        fileExtension: (name as NSString).pathExtension,
        sizeBytes: 1_024,
        modifiedAt: nil,
        source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
    )
}

/// A completed report over the properties given. Warnings and status are set coherently but play no
/// part in any comparison — that is the point of several tests below.
private func report(_ name: String, _ properties: TechnicalProperties) -> InspectionReport {
    InspectionReport(
        file: reference(name),
        properties: properties,
        warnings: [],
        status: .completed
    )
}

/// The all-`unavailable` properties a globally failed inspection produces, straight from the type's
/// own default — the same shape `InspectAudioFileUseCase` builds on its failure path.
private func globallyFailedReport(_ name: String) -> InspectionReport {
    InspectionReport(
        file: reference(name),
        properties: TechnicalProperties(),
        warnings: [
            InspectionWarning(
                code: .metadataModifiedAtUnavailable,
                field: "modifiedAt",
                kind: .unavailable,
                message: "Modification date is not available for this file."
            ),
        ],
        status: .failed(InspectionError(code: .fileUnreadable, message: "could not be opened"))
    )
}

private let flac = TechnicalProperties(
    container: .available("flac"),
    duration: .available(180.0),
    sampleRate: .available(44_100),
    channelCount: .available(2),
    bitDepth: .available(16),
    codec: .available("flac"),
    declaredBitrate: .available(900_000),
    estimatedBitrate: .uncertain(value: 901_233, reason: "estimated from size and duration")
)

@Suite("Domain — comparing two reports")
struct FileComparisonTests {

    // MARK: Coherence — the comparison is derived, never supplied

    /// **Every field is computed from the two reports.** There is no initialiser that accepts a
    /// comparison, so a `FileComparison` claiming the sample rates agree while its reports disagree
    /// cannot be constructed — declaring the two-report initialiser suppresses the memberwise one.
    @Test("every comparison is derived from the two reports")
    func everyComparisonIsDerived() {
        var other = flac
        other.sampleRate = .available(48_000)

        let comparison = FileComparison(first: report("a.flac", flac), second: report("b.flac", other))

        #expect(comparison.sampleRate == .different(first: 44_100, second: 48_000))
        #expect(comparison.container == .same("flac"))
        // And it agrees with what the reports themselves say.
        #expect(comparison.first.properties.sampleRate == .available(44_100))
        #expect(comparison.second.properties.sampleRate == .available(48_000))
    }

    /// The same two reports always produce the same comparison.
    @Test("the comparison is deterministic")
    func theComparisonIsDeterministic() {
        let a = report("a.flac", flac)
        var otherProperties = flac
        otherProperties.bitDepth = .unsupported(reason: "lossy codec")
        let b = report("b.m4a", otherProperties)

        #expect(FileComparison(first: a, second: b) == FileComparison(first: a, second: b))
    }

    /// The reports go in and come out untouched; comparing reads them and changes nothing.
    @Test("the two reports are carried through unchanged")
    func theReportsAreUnchanged() {
        let a = report("a.flac", flac)
        let b = globallyFailedReport("b.wav")

        let comparison = FileComparison(first: a, second: b)

        #expect(comparison.first == a)
        #expect(comparison.second == b)
    }

    // MARK: The eight fields

    @Test("container compares as the same or as different")
    func containerCompares() {
        var wav = flac
        wav.container = .available("wav")

        #expect(FileComparison(first: report("a", flac), second: report("b", flac)).container == .same("flac"))
        #expect(
            FileComparison(first: report("a", flac), second: report("b", wav)).container
                == .different(first: "flac", second: "wav")
        )
    }

    /// **Duration is exact, and gets no special treatment to make it so.** It falls through the same
    /// generic rule as every other field, which is precisely why no tolerance can live anywhere.
    @Test("duration compares exactly, down to one ULP")
    func durationComparesExactly() {
        var barelyLonger = flac
        barelyLonger.duration = .available(180.0.nextUp)

        #expect(FileComparison(first: report("a", flac), second: report("b", flac)).duration == .same(180.0))
        #expect(
            FileComparison(first: report("a", flac), second: report("b", barelyLonger)).duration
                == .different(first: 180.0, second: 180.0.nextUp)
        )
    }

    @Test("sample rate compares as the same or as different")
    func sampleRateCompares() {
        var resampled = flac
        resampled.sampleRate = .available(48_000)

        #expect(FileComparison(first: report("a", flac), second: report("b", flac)).sampleRate == .same(44_100))
        #expect(
            FileComparison(first: report("a", flac), second: report("b", resampled)).sampleRate
                == .different(first: 44_100, second: 48_000)
        )
    }

    @Test("channel count compares as the same or as different")
    func channelCountCompares() {
        var mono = flac
        mono.channelCount = .available(1)

        #expect(FileComparison(first: report("a", flac), second: report("b", flac)).channelCount == .same(2))
        #expect(
            FileComparison(first: report("a", flac), second: report("b", mono)).channelCount
                == .different(first: 2, second: 1)
        )
    }

    /// **The case the whole design exists for.** A lossy file's format cannot express bit depth, and
    /// the honest answer against a file that reports one is that nothing was compared — never that the
    /// two differ, and never a hint that one is worse.
    @Test("bit depth is not comparable when one format cannot express it")
    func bitDepthAgainstAFormatThatCannotExpressIt() {
        var lossy = flac
        lossy.bitDepth = .unsupported(reason: "a lossy codec has no PCM bit depth")

        let comparison = FileComparison(first: report("a.flac", flac), second: report("b.m4a", lossy))

        #expect(comparison.bitDepth == .incomparable(.firstAvailable(second: .unsupported)))
        // Both available still compares normally.
        var deeper = flac
        deeper.bitDepth = .available(24)
        #expect(
            FileComparison(first: report("a", flac), second: report("b", deeper)).bitDepth
                == .different(first: 16, second: 24)
        )
    }

    @Test("codec compares as the same or as different")
    func codecCompares() {
        var aac = flac
        aac.codec = .available("aac")

        #expect(FileComparison(first: report("a", flac), second: report("b", flac)).codec == .same("flac"))
        #expect(
            FileComparison(first: report("a", flac), second: report("b", aac)).codec
                == .different(first: "flac", second: "aac")
        )
    }

    @Test("declared bitrate compares, or reports that one side does not carry it")
    func declaredBitrateCompares() {
        var lower = flac
        lower.declaredBitrate = .available(320_000)
        var absent = flac
        absent.declaredBitrate = .unavailable(reason: nil)

        #expect(
            FileComparison(first: report("a", flac), second: report("b", flac)).declaredBitrate
                == .same(900_000)
        )
        #expect(
            FileComparison(first: report("a", flac), second: report("b", lower)).declaredBitrate
                == .different(first: 900_000, second: 320_000)
        )
        #expect(
            FileComparison(first: report("a", flac), second: report("b", absent)).declaredBitrate
                == .incomparable(.firstAvailable(second: .unavailable))
        )
    }

    /// **Two estimates never compare, however closely they agree.** The reader marks an estimate
    /// `uncertain` by construction, and reporting a coincidence between two unreliable readings as
    /// agreement would promote both to something they are not.
    @Test("two estimated bitrates are not comparable, matching or not")
    func estimatedBitratesNeverCompare() {
        var differentEstimate = flac
        differentEstimate.estimatedBitrate = .uncertain(value: 705_600, reason: "estimated")

        let matching = FileComparison(first: report("a", flac), second: report("b", flac))
        let diverging = FileComparison(first: report("a", flac), second: report("b", differentEstimate))

        #expect(matching.estimatedBitrate == .incomparable(.neitherAvailable(first: .uncertain, second: .uncertain)))
        #expect(diverging.estimatedBitrate == .incomparable(.neitherAvailable(first: .uncertain, second: .uncertain)))
    }

    /// The type permits an available estimate even though the reader does not produce one; if it ever
    /// did, it would fall through the same rule as everything else with no special case.
    @Test("an available estimate would follow the same rule as any other field")
    func anAvailableEstimateFollowsTheGenericRule() {
        var declaredEstimate = flac
        declaredEstimate.estimatedBitrate = .available(900_000)
        var otherEstimate = flac
        otherEstimate.estimatedBitrate = .available(320_000)

        #expect(
            FileComparison(first: report("a", declaredEstimate), second: report("b", declaredEstimate))
                .estimatedBitrate == .same(900_000)
        )
        #expect(
            FileComparison(first: report("a", declaredEstimate), second: report("b", otherEstimate))
                .estimatedBitrate == .different(first: 900_000, second: 320_000)
        )
    }

    /// **The two rates are never crossed.** Their values are chosen so that a crossed comparison would
    /// be visible: the declared rates agree while the estimates do not, and vice versa. A code path
    /// that read one against the other would have to report something other than this.
    @Test("a declared rate is never compared against an estimated one")
    func declaredIsNeverComparedAgainstEstimated() {
        var left = flac
        left.declaredBitrate = .available(900_000)
        left.estimatedBitrate = .available(111_111)
        var right = flac
        right.declaredBitrate = .available(900_000)
        right.estimatedBitrate = .available(222_222)

        let comparison = FileComparison(first: report("a", left), second: report("b", right))

        #expect(comparison.declaredBitrate == .same(900_000))
        #expect(comparison.estimatedBitrate == .different(first: 111_111, second: 222_222))

        // And with the two roles swapped between the fields, the outcomes swap with them.
        var reversedLeft = flac
        reversedLeft.declaredBitrate = .available(111_111)
        reversedLeft.estimatedBitrate = .available(900_000)
        var reversedRight = flac
        reversedRight.declaredBitrate = .available(222_222)
        reversedRight.estimatedBitrate = .available(900_000)

        let reversed = FileComparison(first: report("a", reversedLeft), second: report("b", reversedRight))
        #expect(reversed.declaredBitrate == .different(first: 111_111, second: 222_222))
        #expect(reversed.estimatedBitrate == .same(900_000))
    }

    // MARK: A globally failed report

    /// **A failed inspection is not a failed comparison.** There is no error case and nothing throws:
    /// the failed report's properties are all `unavailable`, so every field reports that nothing was
    /// compared, and the report's own status says why.
    @Test("a globally failed second report compares without failing")
    func aGloballyFailedReportComparesHonestly() {
        let intact = report("a.flac", flac)
        let failed = globallyFailedReport("b.wav")

        let comparison = FileComparison(first: intact, second: failed)

        // Seven fields are available on one side and absent on the other.
        for outcome in [
            comparison.container, comparison.codec,
        ] {
            #expect(outcome == .incomparable(.firstAvailable(second: .unavailable)))
        }
        #expect(comparison.duration == .incomparable(.firstAvailable(second: .unavailable)))
        #expect(comparison.sampleRate == .incomparable(.firstAvailable(second: .unavailable)))
        #expect(comparison.channelCount == .incomparable(.firstAvailable(second: .unavailable)))
        #expect(comparison.bitDepth == .incomparable(.firstAvailable(second: .unavailable)))
        #expect(comparison.declaredBitrate == .incomparable(.firstAvailable(second: .unavailable)))
        // The first side was already uncertain, so neither side had a comparable value.
        #expect(
            comparison.estimatedBitrate
                == .incomparable(.neitherAvailable(first: .uncertain, second: .unavailable))
        )

        // The first report is untouched, and the failed one keeps its own status and warnings —
        // neither of which took part in any comparison.
        #expect(comparison.first == intact)
        #expect(comparison.second.status == .failed(InspectionError(code: .fileUnreadable, message: "could not be opened")))
        #expect(comparison.second.warnings.count == 1)
    }

    /// Two failed reports compare too, and say that neither side had anything.
    @Test("two globally failed reports still compare")
    func twoFailedReportsStillCompare() {
        let comparison = FileComparison(
            first: globallyFailedReport("a.wav"), second: globallyFailedReport("b.wav")
        )
        #expect(comparison.sampleRate == .incomparable(.neitherAvailable(first: .unavailable, second: .unavailable)))
        #expect(comparison.duration == .incomparable(.neitherAvailable(first: .unavailable, second: .unavailable)))
    }

    /// **A report compared against itself**, which is what the domain sees when the same file is
    /// inspected twice. Every comparable property agrees — and the estimate still does not compare,
    /// which is the "nothing further is claimed" half: identical facts are not a statement that the two
    /// are one file.
    @Test("a report compared against itself agrees on every comparable property")
    func aReportComparedAgainstItself() {
        let same = report("a.flac", flac)
        let comparison = FileComparison(first: same, second: same)

        #expect(comparison.container == .same("flac"))
        #expect(comparison.duration == .same(180.0))
        #expect(comparison.sampleRate == .same(44_100))
        #expect(comparison.channelCount == .same(2))
        #expect(comparison.bitDepth == .same(16))
        #expect(comparison.codec == .same("flac"))
        #expect(comparison.declaredBitrate == .same(900_000))
        // Not `same`: an unreliable reading is no more comparable against itself than against another.
        #expect(
            comparison.estimatedBitrate
                == .incomparable(.neitherAvailable(first: .uncertain, second: .uncertain))
        )
    }

    // MARK: Exchanging the two reports

    /// **Exchanging the two reports exchanges the evidence, and nothing else.** The representation
    /// keeps which side was which, so this is not symmetry: `same` is unchanged because it carries one
    /// value, while `different` and `incomparable` report their two sides in the other order.
    @Test("exchanging the two reports exchanges the sides of every outcome")
    func exchangingTheReportsExchangesTheSides() {
        var other = flac
        other.sampleRate = .available(48_000)
        other.bitDepth = .unsupported(reason: "lossy")

        let a = report("a.flac", flac)
        let b = report("b.m4a", other)

        let forward = FileComparison(first: a, second: b)
        let exchanged = FileComparison(first: b, second: a)

        // `same` carries one value, so it reads identically either way.
        #expect(forward.container == .same("flac"))
        #expect(exchanged.container == .same("flac"))

        // `different` reports the same two values with the sides exchanged.
        #expect(forward.sampleRate == .different(first: 44_100, second: 48_000))
        #expect(exchanged.sampleRate == .different(first: 48_000, second: 44_100))

        // `incomparable` reports the same two states with the sides exchanged.
        #expect(forward.bitDepth == .incomparable(.firstAvailable(second: .unsupported)))
        #expect(exchanged.bitDepth == .incomparable(.secondAvailable(first: .unsupported)))

        // The reports follow their sides.
        #expect(forward.first == a)
        #expect(exchanged.first == b)
    }
}

// MARK: - What the type must not hold

/// **The shape of `FileComparison`, checked rather than described.**
///
/// `Mirror` reports a struct's **stored** properties, so the exact set of them is a real runtime
/// question with a real answer — not a search for a string in a source file. That is enough to
/// establish both halves of what this slice promises: the eight compared fields are there, and nothing
/// else is.
///
/// **Its one limitation, stated rather than glossed:** `Mirror` does not see *computed* members, so a
/// `var allSame: Bool { … }` added later would not fail this test. Swift exposes no reflection over
/// methods or computed properties, so that half stays an audit of the public surface, carried by the
/// type's documentation and by review. A green check that could not detect the thing it names would be
/// worse than saying so.
@Suite("Domain — what a file comparison must not hold")
struct FileComparisonProhibitionTests {

    private var comparison: FileComparison {
        FileComparison(first: report("a.flac", flac), second: report("b.flac", flac))
    }

    private var storedProperties: Set<String> {
        Set(Mirror(reflecting: comparison).children.compactMap(\.label))
    }

    /// The eight compared fields, the two reports, and **nothing else**.
    @Test("it stores exactly the two reports and the eight comparisons")
    func itStoresExactlyWhatItShould() {
        #expect(storedProperties == [
            "first", "second",
            "container", "duration", "sampleRate", "channelCount",
            "bitDepth", "codec", "declaredBitrate", "estimatedBitrate",
        ])
    }

    /// **Context is carried by the reports, never as a comparison.** These are shown beside each file's
    /// facts and deliberately never judged, so no comparison for them exists to be rendered as one.
    @Test("nothing that is context is stored as a comparison")
    func contextIsNotCompared() {
        for name in [
            "fileExtension", "sizeBytes", "displayName", "modifiedAt", "source", "id",
            "warnings", "status",
        ] {
            #expect(!storedProperties.contains(name), "\(name) must be context, not a comparison")
        }
        // They remain reachable from the reports, which is where a surface reads them.
        #expect(comparison.first.file.sizeBytes == 1_024)
        #expect(comparison.second.status == .completed)
    }

    /// No aggregate is stored: not a score, not a count, not a single bit standing in for one.
    @Test("no aggregate of the comparison is stored")
    func noAggregateIsStored() {
        for name in [
            "differenceCount", "allSame", "isSame", "isIdentical", "matches",
            "winner", "preferred", "better", "worse", "score", "similarity", "confidence",
        ] {
            #expect(!storedProperties.contains(name), "\(name) would be a verdict")
        }
    }

    /// **No ordering, and it never reaches the exporter.** Both are conformances, so their absence is
    /// a genuine runtime question — a positive control confirms the check answers `true` for a type
    /// that does conform.
    @Test("it is neither Comparable nor Codable")
    func itIsNeitherComparableNorCodable() {
        #expect(!(FileComparison.self is any Comparable.Type))
        #expect(!(FileComparison.self is any Encodable.Type))
        #expect(!(FileComparison.self is any Decodable.Type))
    }
}
