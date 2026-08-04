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
}

/// One presentable property row. `value` exists **only** where the domain carries one, so nothing is
/// fabricated. `detail` carries the reason, or the exact technical token behind a humanised value —
/// a summary always keeps a visible path back to the precise datum.
struct PropertyDisplay: Equatable, Identifiable {
    let name: String
    let state: PropertyPresentationState
    let value: String?
    let unit: String?
    let detail: String?

    var id: String { name }
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
            "Read \(read) of \(total) properties. The rest are not present in the file or not defined by this format."
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
}

/// Turns the domain report into presentable rows. Pure and deterministic, so it is unit-tested without
/// any view.
enum ReportPropertyFormatter {

    // MARK: - Properties

    /// The eight rows, in declaration order. Declared and estimated bitrate stay separate.
    static func displays(for properties: TechnicalProperties) -> [PropertyDisplay] {
        [
            display("Container", properties.container, unit: nil, format: containerName, technicalToken: { $0 }),
            display("Duration", properties.duration, unit: "seconds") { String($0) },
            display("Sample rate", properties.sampleRate, unit: "hertz") { String($0) },
            display("Channel count", properties.channelCount, unit: nil) { String($0) },
            display("Bit depth", properties.bitDepth, unit: "bits") { String($0) },
            display("Codec", properties.codec, unit: nil, format: codecName, technicalToken: { $0 }),
            display("Declared bitrate", properties.declaredBitrate, unit: "bitsPerSecond") { String($0) },
            display("Estimated bitrate", properties.estimatedBitrate, unit: "bitsPerSecond") { String($0) },
        ]
    }

    /// Maps one `Property<Value>` to its row, preserving every state distinctly and never fabricating a
    /// value. `technicalToken` optionally yields the exact underlying token, kept as detail so a
    /// humanised name never hides the precise datum.
    static func display<Value>(
        _ name: String,
        _ property: Property<Value>,
        unit: String?,
        format: (Value) -> String,
        technicalToken: ((Value) -> String)? = nil
    ) -> PropertyDisplay {
        switch property {
        case let .available(value):
            PropertyDisplay(
                name: name,
                state: .measured,
                value: format(value),
                unit: unit,
                detail: preservedToken(value, format: format, technicalToken: technicalToken)
            )
        case let .unavailable(reason):
            PropertyDisplay(name: name, state: .notPresent, value: nil, unit: nil, detail: reason)
        case let .unsupported(reason):
            PropertyDisplay(name: name, state: .notDefinedByFormat, value: nil, unit: nil, detail: reason)
        case let .uncertain(value, reason):
            PropertyDisplay(
                name: name,
                state: .readButUnreliable,
                value: value.map(format),
                unit: value == nil ? nil : unit,
                detail: uncertainDetail(value, reason: reason, format: format, technicalToken: technicalToken)
            )
        case let .failed(failure):
            // The stable code stays in the JSON, where it is the identity; here only the message.
            PropertyDisplay(name: name, state: .couldNotBeRead, value: nil, unit: nil, detail: failure.message)
        }
    }

    /// Convenience for the fields whose presentable value is their raw value.
    static func display<Value>(
        _ name: String,
        _ property: Property<Value>,
        unit: String?,
        _ format: @escaping (Value) -> String
    ) -> PropertyDisplay {
        display(name, property, unit: unit, format: format, technicalToken: nil)
    }

    /// The exact token, shown only when the humanised name actually differs from it.
    private static func preservedToken<Value>(
        _ value: Value,
        format: (Value) -> String,
        technicalToken: ((Value) -> String)?
    ) -> String? {
        guard let technicalToken else { return nil }
        let token = technicalToken(value)
        return token == format(value) ? nil : token
    }

    private static func uncertainDetail<Value>(
        _ value: Value?,
        reason: String,
        format: (Value) -> String,
        technicalToken: ((Value) -> String)?
    ) -> String {
        guard let value, let token = preservedToken(value, format: format, technicalToken: technicalToken) else {
            return reason
        }
        return "\(token) — \(reason)"
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
