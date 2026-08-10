import AudioInspectorDomain
import UniformTypeIdentifiers

/// What the report can say about one property, in the user's terms. A **closed** enum owned by the
/// presentation layer and deliberately decoupled from both the domain's `Property` cases and the wire
/// tokens, so renaming either can never silently change what a person reads.
///
/// The mapping from the domain stays one-to-one: no distinction the domain makes is lost.
enum PropertyPresentationState: Equatable, CaseIterable, Sendable {
    /// Read cleanly. Carries **no label** — the value speaks for itself.
    case measured
    /// The file simply does not carry it.
    case notPresent
    /// The format has no such concept.
    case notDefinedByFormat
    /// Read, but not dependable; a reason always accompanies it.
    case readButUnreliable
    /// Reading it failed.
    case couldNotBeRead

    /// Plain words, or `nil` for a cleanly measured value. None of these characterises the file: an
    /// absent or undefined property is an ordinary outcome of reading a format, never a defect.
    var label: String? {
        switch self {
        case .measured: nil
        case .notPresent: "Not present in the file"
        case .notDefinedByFormat: "Not defined by this format"
        case .readButUnreliable: "Read, but not reliable"
        case .couldNotBeRead: "Could not be read"
        }
    }

    /// The one distinction worth a symbol: "the format has no such concept" versus "reading it failed"
    /// are semantically different and look identical in text alone. `nil` everywhere else — an icon
    /// tied to a value would start to look like a verdict.
    ///
    /// A symbol never appears without its label, so nothing depends on seeing it.
    var symbolName: String? {
        switch self {
        case .measured, .notPresent, .readButUnreliable: nil
        case .notDefinedByFormat: "minus.circle"
        case .couldNotBeRead: "exclamationmark.triangle"
        }
    }

    /// Whether this state is a genuine failure of the *reading*. Only this one earns an alerting
    /// colour; `readButUnreliable` and `notDefinedByFormat` are ordinary results, and colouring them
    /// would tell the user their file is worse — which is not something presentation may say.
    var isReadFailure: Bool { self == .couldNotBeRead }
}

/// One presentable property row. `value` exists **only** where the domain carries one, so nothing is
/// fabricated, and it is self-contained: the unit is part of it (`44.1 kHz`), never a separate wire
/// name such as `hertz`. `detail` carries the reason, or the exact figure behind a rounded value — a
/// summary always keeps a visible path back to the precise datum.
struct PropertyDisplay: Equatable, Identifiable {
    let name: String
    let state: PropertyPresentationState
    let value: String?
    let detail: String?

    var id: String { name }

    /// One sentence for an assistive reader, so a row is announced as a coherent whole instead of as
    /// four loose fragments. It carries the same information the row shows, in the same order.
    var accessibilityLabel: String {
        [name, value, state.label, detail]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// How an inspection ended, said as a statement about the reading rather than about the audio.
///
/// The domain's `completed` / `partial` / `failed` are case names, and `partial` additionally describes
/// how the *analysis* ran, not what the file is — a user reading it cannot tell whether the problem is
/// their file or the app. These say what happened, without implying anything about quality.
enum InspectionOutcomeDisplay: Equatable {
    case allRead(count: Int)
    case someNotRead(read: Int, total: Int)
    case couldNotInspect(message: String)

    var text: String {
        switch self {
        case let .allRead(count):
            "Read all \(count) properties this format exposes."
        case let .someNotRead(read, total):
            "Read \(read) of \(total) properties cleanly. Each of the remaining \(total - read) shows what is known about it."
        case let .couldNotInspect(message):
            message
        }
    }
}

/// One presentable warning. The stable `code` is deliberately absent: it is the JSON contract's
/// identity, not something to read. `subject` is the property's presentable name, or `nil` when the
/// warning is not about a specific property — in which case no label is shown, rather than inventing one.
struct WarningDisplay: Equatable, Identifiable {
    let id: Int
    let subject: String?
    let message: String
    let state: PropertyPresentationState

    /// Announced as one sentence, subject first when there is one.
    var accessibilityLabel: String {
        [subject, message].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The few facts that answer "what is this file?" at a glance, above the detail.
///
/// Every entry comes from a property the reader actually produced: a value that was not read is simply
/// absent from the summary rather than filled in with a placeholder.
struct ReportSummary: Equatable {
    let fileName: String
    /// Format, sample rate, channels, duration, size — in that order, omitting whatever is missing.
    let highlights: [String]
}

/// One named group of property rows, so the report reads as sections rather than a flat list.
struct PropertyGroup: Equatable, Identifiable {
    let name: String
    let properties: [PropertyDisplay]

    var id: String { name }
}

/// Turns the domain report into presentable rows. Pure and deterministic, so it is unit-tested without
/// any view.
enum ReportPropertyFormatter {

    // MARK: - Properties

    /// The nine rows, in declaration order. Declared, estimated and average-file bitrate stay separate —
    /// three different claims about a rate, never merged (ADR-0018).
    ///
    /// Each numeric field pairs a readable form with the exact one, so rounding never loses the datum.
    static func displays(for properties: TechnicalProperties) -> [PropertyDisplay] {
        [
            display("Container", properties.container, format: containerName, exact: { $0 }),
            display("Duration", properties.duration, format: { HumanFormat.duration($0) ?? HumanFormat.durationExact($0) }, exact: HumanFormat.durationExact),
            display("Sample rate", properties.sampleRate, format: HumanFormat.sampleRate, exact: HumanFormat.sampleRateExact),
            display("Channel count", properties.channelCount, format: HumanFormat.channels, exact: HumanFormat.channelsExact),
            display("Bit depth", properties.bitDepth, format: HumanFormat.bitDepth, exact: nil),
            display("Codec", properties.codec, format: codecName, exact: { $0 }),
            display("Declared bitrate", properties.declaredBitrate, format: HumanFormat.bitrate, exact: HumanFormat.bitrateExact),
            display("Estimated bitrate", properties.estimatedBitrate, format: HumanFormat.bitrate, exact: HumanFormat.bitrateExact),
            display("Average file bitrate", properties.averageFileBitrate, format: HumanFormat.bitrate, exact: HumanFormat.bitrateExact),
        ]
    }

    /// Maps one `Property<Value>` to its row, preserving every state distinctly and never fabricating a
    /// value. `exact` yields the precise underlying figure or token, kept as detail so a readable form
    /// never hides it.
    static func display<Value>(
        _ name: String,
        _ property: Property<Value>,
        format: (Value) -> String,
        exact: ((Value) -> String)?
    ) -> PropertyDisplay {
        switch property {
        case let .available(value):
            PropertyDisplay(
                name: name,
                state: .measured,
                value: format(value),
                detail: preservedExact(value, format: format, exact: exact)
            )
        case let .unavailable(reason):
            PropertyDisplay(name: name, state: .notPresent, value: nil, detail: reason)
        case let .unsupported(reason):
            PropertyDisplay(name: name, state: .notDefinedByFormat, value: nil, detail: reason)
        case let .uncertain(value, reason):
            PropertyDisplay(
                name: name,
                state: .readButUnreliable,
                value: value.map(format),
                detail: uncertainDetail(value, reason: reason, format: format, exact: exact)
            )
        case let .failed(failure):
            // The stable code stays in the JSON, where it is the identity; here only the message.
            PropertyDisplay(name: name, state: .couldNotBeRead, value: nil, detail: failure.message)
        }
    }

    /// The exact figure, shown only when the readable form actually differs from it.
    private static func preservedExact<Value>(
        _ value: Value,
        format: (Value) -> String,
        exact: ((Value) -> String)?
    ) -> String? {
        guard let exact else { return nil }
        let precise = exact(value)
        return precise == format(value) ? nil : precise
    }

    private static func uncertainDetail<Value>(
        _ value: Value?,
        reason: String,
        format: (Value) -> String,
        exact: ((Value) -> String)?
    ) -> String {
        guard let value, let precise = preservedExact(value, format: format, exact: exact) else {
            return reason
        }
        return "\(precise) — \(reason)"
    }

    // MARK: - Technical tokens with human names

    /// Codec tokens the project produces, named only where the name is certain. **An unrecognised token
    /// is returned unchanged**: guessing a name would invent information the reader never established.
    private static let codecNames: [String: String] = [
        "lpcm": "Linear PCM",
        "aac": "AAC",
        "alac": "Apple Lossless (ALAC)",
        "flac": "FLAC",
        "opus": "Opus",
        "vorb": "Vorbis",
    ]

    static func codecName(_ token: String) -> String {
        codecNames[token.lowercased()] ?? token
    }

    /// The container arrives as a Uniform Type Identifier. The system's own localized description is
    /// used when it resolves; **an unknown identifier is shown as it is**, never described by guesswork.
    static func containerName(_ identifier: String) -> String {
        guard let description = UTType(identifier)?.localizedDescription, !description.isEmpty else {
            return identifier
        }
        return description
    }

    // MARK: - Warnings

    /// Wire keys translated to the names the rows use. A key with no entry keeps its own text rather
    /// than being dropped, so a future field is never silently hidden.
    private static let fieldNames: [String: String] = [
        "container": "Container",
        "duration": "Duration",
        "sampleRate": "Sample rate",
        "channelCount": "Channel count",
        "bitDepth": "Bit depth",
        "codec": "Codec",
        "declaredBitrate": "Declared bitrate",
        "estimatedBitrate": "Estimated bitrate",
        "sizeBytes": "Size",
        "modifiedAt": "Modified",
    ]

    static func displays(for warnings: [InspectionWarning]) -> [WarningDisplay] {
        warnings.enumerated().map { index, warning in
            WarningDisplay(
                id: index,
                subject: warning.field.map { fieldNames[$0] ?? $0 },
                message: warning.message,
                state: state(for: warning.kind)
            )
        }
    }

    static func state(for kind: WarningKind) -> PropertyPresentationState {
        switch kind {
        case .unavailable: .notPresent
        case .unsupported: .notDefinedByFormat
        case .uncertain: .readButUnreliable
        case .failed: .couldNotBeRead
        }
    }

    // MARK: - Grouping and summary

    /// Two groups: what the file **is**, and how it is **encoded**. Every one of the nine rows appears
    /// in exactly one group, so grouping reorganises without hiding anything.
    static func groups(for properties: TechnicalProperties) -> [PropertyGroup] {
        let rows = displays(for: properties)
        func pick(_ names: [String]) -> [PropertyDisplay] {
            names.compactMap { name in rows.first { $0.name == name } }
        }
        return [
            PropertyGroup(name: "Format", properties: pick(["Container", "Codec", "Duration"])),
            PropertyGroup(
                name: "Encoding",
                properties: pick([
                    "Sample rate", "Channel count", "Bit depth",
                    "Declared bitrate", "Estimated bitrate", "Average file bitrate",
                ])
            ),
        ]
    }

    /// The glance-level answer: name, then the handful of facts that identify the file. Anything the
    /// reader could not establish is left out rather than guessed.
    static func summary(for report: InspectionReport) -> ReportSummary {
        let rows = displays(for: report.properties)
        func value(_ name: String) -> String? {
            rows.first { $0.name == name }?.value
        }
        var highlights = [
            value("Codec") ?? value("Container"),
            value("Sample rate"),
            value("Channel count"),
            value("Duration"),
        ].compactMap { $0 }
        if let size = report.file.sizeBytes {
            highlights.append(HumanFormat.byteCount(size))
        }
        return ReportSummary(fileName: report.file.displayName, highlights: highlights)
    }

    // MARK: - Outcome

    /// Derives the outcome from the rows, so the count shown always matches the rows on screen.
    static func outcome(for status: InspectionStatus, properties: [PropertyDisplay]) -> InspectionOutcomeDisplay {
        if case let .failed(error) = status {
            return .couldNotInspect(message: error.message)
        }
        let read = properties.count { $0.state == .measured }
        return read == properties.count
            ? .allRead(count: properties.count)
            : .someNotRead(read: read, total: properties.count)
    }
}
