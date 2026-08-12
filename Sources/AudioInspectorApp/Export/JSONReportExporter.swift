import AudioInspectorDomain
import Foundation

/// The concrete `ReportExporting`: maps the domain report to the v1 DTO and serializes it with a
/// centralized, stable `JSONEncoder`. It owns the envelope's two injected inputs — the export clock
/// and the generator identity — so neither is coupled to wall-clock time or the app bundle:
///
/// - `now` is evaluated **on every** `export`, so `generatedAt` is the export instant (not the
///   inspection instant, ADR-0009); tests inject a fixed clock.
/// - `generator` is injected, so tests assert a deterministic name/version.
///
/// It never touches a `URL` or the filesystem — encoding only (group 5 owns writing).
struct JSONReportExporter: ReportExporting {
    private let generator: ReportGenerator
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - generator: the envelope's `generator` identity (injected — never read from the bundle here).
    ///   - now: the export clock, called once per `export` to stamp `generatedAt`. Defaults to the
    ///     live system clock; tests pass a fixed instant.
    init(generator: ReportGenerator, now: @escaping @Sendable () -> Date = { Date() }) {
        self.generator = generator
        self.now = now
    }

    func export(
        _ report: InspectionReport,
        signalLevelMetrics: SignalLevelMetrics?,
        truePeak: TruePeakMeasurement?
    ) throws -> Data {
        let envelope = InspectionReportMapper.envelope(
            for: report, signalLevelMetrics: signalLevelMetrics, truePeak: truePeak,
            generatedAt: now(), generator: generator
        )
        return try Self.makeEncoder().encode(envelope)
    }

    /// The single, stable encoder configuration:
    /// - `.iso8601` dates → UTC, `Z`-suffixed, second precision (matches the schema's date format);
    /// - `.sortedKeys` → deterministic output for fixtures (key order is not a semantic contract);
    /// - the **default** non-conforming-float strategy (`.throw`) is kept, so `Double.nan`/`±infinity`
    ///   fail encoding rather than emitting a fictional value. No pretty-printing (not required).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
