/// What comparing the observable technical facts of two inspected files establishes.
///
/// It answers exactly one question — *which technical facts are the same, different, or not
/// comparable between these two files?* — and refuses the ones it cannot answer honestly: whether they
/// hold the same recording, whether one derives from the other, which has more quality, and which to
/// keep (ADR-0017).
///
/// ## Derived, never assembled
///
/// The only way to build one is from **two reports**. The comparisons are computed here, from those
/// reports, and cannot be supplied: a `FileComparison` whose `sampleRate` says *same* while its two
/// reports say 44 100 and 48 000 would be a lie the type could tell, so the type cannot tell it.
/// Declaring this initialiser is what suppresses the memberwise one that would otherwise accept
/// arbitrary results.
///
/// ## Both reports are kept whole
///
/// Not copied field by field. The surface needs each file's own facts, warnings and status anyway —
/// and the things this deliberately does **not** compare (`fileExtension`, `sizeBytes`, `modifiedAt`,
/// `displayName`, `source`, `id`, the warnings and the status) are context a reader still wants to
/// see. Keeping the reports means there is one copy of each fact rather than two that can drift, and
/// it is also where `ComparisonGap`'s missing detail lives: the gap says a side was `unsupported`, and
/// the reason it was is on the property inside the report.
///
/// ## One field per technical property, named explicitly
///
/// Exactly the fields `TechnicalProperties` holds — **all of them**, which the spec requires in as many
/// words: *"For every technical property both reports carry … the set SHALL be exhaustive, so no
/// property is left without an outcome."* **There is no `format` property** — `container` and `codec`
/// are separate technical facts, and the project treats that distinction as load-bearing.
///
/// They are stored comparisons rather than a dictionary keyed by some property identifier,
/// deliberately: the contract is visible in the type, each carries its own `Value`, and nothing needs
/// type erasure or `Any` to hold them together.
///
/// **The count is not the contract; the coverage is.** This type was born with eight fields and went a
/// release without the ninth, because nothing tied it to `TechnicalProperties`. `ComparisonPropertyCoverageTests`
/// now asserts the correspondence over `Mirror`, so a tenth property fails on the day it is added
/// rather than quietly losing its row.
///
/// ## What it cannot express
///
/// **No identity, no lifecycle, no timestamp.** A comparison is derived data, not an entity.
///
/// **No aggregate of any kind.** No score, no similarity, no confidence, no count of differences, and
/// no `allSame`, `isIdentical` or `matches` — the last of those being the most tempting, because a
/// boolean looks like a convenience rather than a verdict. *"Every comparable property agreed"* and
/// *"the two files are the same"* are different statements, and one bit cannot hold both. A caller
/// that wants the first reads the eight outcomes.
///
/// **No ordering and no preferred side.** `first` and `second` are the order the user supplied them —
/// the file already open, then the file chosen for comparison. Nothing here derives a rank from that.
///
/// ## Not `Codable`
///
/// It never enters the `schemaVersion` 1 export, which describes **one** file. Conforming it would
/// advertise a contract that does not exist.
public struct FileComparison: Sendable, Equatable {
    /// The file already open when the comparison was asked for.
    public let first: InspectionReport
    /// The file chosen to compare against it.
    public let second: InspectionReport

    public let container: PropertyComparison<String>
    public let duration: PropertyComparison<Double>
    public let sampleRate: PropertyComparison<Int>
    public let channelCount: PropertyComparison<Int>
    public let bitDepth: PropertyComparison<Int>
    public let codec: PropertyComparison<String>
    /// Compared **only** against the other file's declared rate.
    public let declaredBitrate: PropertyComparison<Int>
    /// Compared **only** against the other file's estimated rate. In practice almost always
    /// `incomparable`: the reader marks an estimate `uncertain` by construction, and an unreliable
    /// reading is not a comparable fact however closely it matches another (ADR-0017).
    public let estimatedBitrate: PropertyComparison<Int>
    /// The whole file's average rate, compared only against the other file's own average.
    ///
    /// Like `estimatedBitrate` it is almost always `incomparable` in practice, and for the same reason:
    /// `AVFoundationAudioFilePropertyReader` has no path that returns it as anything but `uncertain`
    /// (ADR-0018). That is not a special case here — it is the generic rule applied to a property whose
    /// state happens to be constant, and no exception is made to let an estimate compare.
    public let averageFileBitrate: PropertyComparison<Int>

    /// Compares two reports. Pure, total and deterministic: no port, no I/O, no `URL`, no framework,
    /// nothing to await and nothing that can fail.
    ///
    /// **A failed report is not a failed comparison.** A report whose inspection failed globally
    /// carries properties that are all `unavailable`, so every field comes out `incomparable` and the
    /// reports themselves say why. There is no error case here, because nothing here can go wrong.
    ///
    /// Every field goes through the **same** generic rule, which is why none can drift from it: there
    /// is no per-field logic for a special case to hide in, and no field-specific tolerance to add.
    /// Duration is a `Double` compared by that same rule, so its equality is exact.
    ///
    /// **No two rates of different kinds are ever compared.** Declared, estimated and whole-file average
    /// are three different things; each pairing below reads the **same** field from both sides, and there
    /// is no expression that crosses them.
    public init(first: InspectionReport, second: InspectionReport) {
        self.first = first
        self.second = second

        let a = first.properties
        let b = second.properties

        container = PropertyComparison(first: a.container, second: b.container)
        duration = PropertyComparison(first: a.duration, second: b.duration)
        sampleRate = PropertyComparison(first: a.sampleRate, second: b.sampleRate)
        channelCount = PropertyComparison(first: a.channelCount, second: b.channelCount)
        bitDepth = PropertyComparison(first: a.bitDepth, second: b.bitDepth)
        codec = PropertyComparison(first: a.codec, second: b.codec)
        declaredBitrate = PropertyComparison(first: a.declaredBitrate, second: b.declaredBitrate)
        estimatedBitrate = PropertyComparison(first: a.estimatedBitrate, second: b.estimatedBitrate)
        averageFileBitrate = PropertyComparison(first: a.averageFileBitrate, second: b.averageFileBitrate)
    }
}
