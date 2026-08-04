import AudioInspectorDomain

/// A flat, presentable view of one technical property — the display analogue of the domain's
/// exhaustive `Property` sum type. It never invents a value: `value` is present **only** where the
/// domain carries one (`available`, or `uncertain` with a value), and `unit` accompanies a value
/// only. `detail` carries the reason (`unavailable`/`unsupported`/`uncertain`) or the stable failure
/// `code: message` (`failed`). This mirrors the JSON wire rules but is an independent UI concern.
struct PropertyDisplay: Equatable, Identifiable {
    let name: String
    let state: String
    let value: String?
    let unit: String?
    let detail: String?

    var id: String { name }
}

/// Turns the domain `TechnicalProperties` into the eight presentable rows, in a fixed order, each
/// preserving its state distinctly. Pure and deterministic, so it is unit-tested without any view.
enum ReportPropertyFormatter {
    /// The eight rows, in declaration order. Declared and estimated bitrate are separate rows.
    static func displays(for properties: TechnicalProperties) -> [PropertyDisplay] {
        [
            display("Container", properties.container, unit: nil) { $0 },
            display("Duration", properties.duration, unit: "seconds") { String($0) },
            display("Sample rate", properties.sampleRate, unit: "hertz") { String($0) },
            display("Channel count", properties.channelCount, unit: nil) { String($0) },
            display("Bit depth", properties.bitDepth, unit: "bits") { String($0) },
            display("Codec", properties.codec, unit: nil) { $0 },
            display("Declared bitrate", properties.declaredBitrate, unit: "bitsPerSecond") { String($0) },
            display("Estimated bitrate", properties.estimatedBitrate, unit: "bitsPerSecond") { String($0) },
        ]
    }

    /// Maps one `Property<Value>` to its presentable row, preserving each state distinctly and never
    /// fabricating a value. `format` renders a carried value to text; it is applied only when a value
    /// actually exists.
    static func display<Value>(
        _ name: String,
        _ property: Property<Value>,
        unit: String?,
        _ format: (Value) -> String
    ) -> PropertyDisplay {
        switch property {
        case let .available(value):
            PropertyDisplay(name: name, state: "available", value: format(value), unit: unit, detail: nil)
        case let .unavailable(reason):
            PropertyDisplay(name: name, state: "unavailable", value: nil, unit: nil, detail: reason)
        case let .unsupported(reason):
            PropertyDisplay(name: name, state: "unsupported", value: nil, unit: nil, detail: reason)
        case let .uncertain(value, reason):
            uncertainDisplay(name, value: value.map(format), unit: unit, reason: reason)
        case let .failed(failure):
            PropertyDisplay(
                name: name,
                state: "failed",
                value: nil,
                unit: nil,
                detail: "\(failure.code.rawValue): \(failure.message)"
            )
        }
    }

    private static func uncertainDisplay(_ name: String, value: String?, unit: String?, reason: String) -> PropertyDisplay {
        PropertyDisplay(name: name, state: "uncertain", value: value, unit: value == nil ? nil : unit, detail: reason)
    }
}
