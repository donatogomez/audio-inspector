import Foundation
import Testing

// Group 9's fifth subject: **the restrictions task 9.6 names, each one asserted** (task 9.6).
//
// `Scripts/check-boundaries.sh` is the gate and stays the gate: it runs in CI and before every push,
// and it covers ten rules across every module. This suite is not a second copy of it. It exists
// because 9.6 does not ask for *the script is green* — it enumerates four specific restrictions and a
// fifth about the ports, and a task that names a property is closed by asserting **that** property.
// The lesson is `add-static-spectrogram-visualization` 10.4's, recorded in ADR-0025: a check written
// as one property and run against a stronger one proves neither.
//
// So each restriction is read off the sources here, by name, and a failure says which one broke
// rather than that something did.
//
// Comment lines are excluded exactly as the script excludes them, and for the same reason: these
// files legitimately explain, at length, that they never handle a `URL`.

@Suite("Architecture — the boundaries this change had to respect")
struct ArchitectureBoundaryTests {

    // MARK: - Reading the sources

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/AudioInspectorKitTests/<this file>
            .deletingLastPathComponent()      // Tests/AudioInspectorKitTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repository root
    }

    /// Every `.swift` file under `Sources/<module>`, as (path relative to the module, lines).
    private func sources(of module: String) throws -> [(path: String, lines: [String])] {
        let directory = Self.repositoryRoot.appendingPathComponent("Sources/\(module)")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        #expect(!files.isEmpty, "\(module) has no sources — the check would pass vacuously")
        return try files.map { path in
            let text = try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
            return (path, text.components(separatedBy: .newlines))
        }
    }

    /// A line that is not a comment. `//`, `///` and the `*` continuation of a block comment, which
    /// is the same set the script skips.
    private func isCode(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
    }

    /// Every module/type name used in `module`'s code, reported with the file and line so a failure
    /// names the offender.
    private func codeLines(of module: String) throws -> [(location: String, line: String)] {
        try sources(of: module).flatMap { file in
            file.lines.enumerated()
                .filter { isCode($0.element) }
                .map { ("\(module)/\(file.path):\($0.offset + 1)", $0.element) }
        }
    }

    private func imports(of module: String) throws -> Set<String> {
        var found: Set<String> = []
        for entry in try codeLines(of: module) {
            let trimmed = entry.line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { continue }
            found.insert(String(trimmed.dropFirst("import ".count))
                .trimmingCharacters(in: .whitespaces))
        }
        return found
    }

    // MARK: - 9.6 · no media framework, no Accelerate, no URL in either feature

    /// **The two feature modules import no media framework.** The pair's drawings are values the app
    /// already produced; presenting them needed nothing that decodes.
    @Test("no feature module imports a media framework", arguments: ["FeatureImport", "FeatureAnalysis"])
    func noMediaFrameworkInFeatures(module: String) throws {
        let imported = try imports(of: module)
        for framework in ["AVFoundation", "AVFAudio", "AudioToolbox", "CoreAudio"] {
            #expect(!imported.contains(framework), "\(module) imports \(framework)")
        }
    }

    /// **Neither feature imports Accelerate.** Accelerate is `AudioInspectorAnalysis`'s alone; a
    /// paired axis is arithmetic over two stream descriptions and needs no transform.
    @Test("no feature module imports Accelerate", arguments: ["FeatureImport", "FeatureAnalysis"])
    func noAccelerateInFeatures(module: String) throws {
        #expect(!(try imports(of: module).contains("Accelerate")), "\(module) imports Accelerate")
    }

    /// **Neither feature uses the `URL` type** (ADR-0010, ADR-0014). A feature is location-free: the
    /// composition root hands it an opaque action, never a place on a disk.
    @Test("no feature module uses the URL type", arguments: ["FeatureImport", "FeatureAnalysis"])
    func noURLInFeatures(module: String) throws {
        for entry in try codeLines(of: module) {
            #expect(
                entry.line.range(of: "\\bURL\\b", options: .regularExpression) == nil,
                "\(entry.location) uses URL: \(entry.line.trimmingCharacters(in: .whitespaces))"
            )
        }
    }

    /// **Neither feature reaches a concrete implementation module.** A feature sees the domain, and
    /// what the composition root hands it.
    @Test("no feature module imports a concrete module", arguments: ["FeatureImport", "FeatureAnalysis"])
    func featuresSeeOnlyTheDomain(module: String) throws {
        let imported = try imports(of: module)
        for concrete in ["AudioInspectorMedia", "AudioInspectorAnalysis", "AudioInspectorApp", "AudioInspectorTesting"] {
            #expect(!imported.contains(concrete), "\(module) imports \(concrete)")
        }
        // And `FeatureAnalysis` never reaches into `FeatureImport`, nor the reverse: the two are
        // siblings joined only at the composition root, which is what lets the pair be assembled
        // there rather than by one feature reading another's state.
        #expect(!imported.contains("FeatureImport") || module == "FeatureImport")
        #expect(!imported.contains("FeatureAnalysis") || module == "FeatureAnalysis")
    }

    // MARK: - 9.6 · no framework type in any port

    /// **No framework type crosses a domain port.** The three ports are read and every type named in
    /// a signature is checked against the frameworks a port may not speak.
    ///
    /// The domain's own purity is the script's rule 1 and is not restated here; what 9.6 names is the
    /// **ports**, which are the seams a framework type would cross by.
    @Test("no port names a framework type")
    func portsSpeakNoFramework() throws {
        let ports = Self.repositoryRoot.appendingPathComponent("Sources/AudioInspectorDomain/Ports")
        let files = try FileManager.default.contentsOfDirectory(atPath: ports.path)
            .filter { $0.hasSuffix(".swift") }.sorted()
        #expect(files.count == 3, "expected the three known ports, found \(files)")

        // Types that only exist because a framework does. `Data` and `Date` are Foundation **value**
        // types and are allowed in the domain by ADR-0005; a reference type from a framework is not.
        let forbidden = [
            "AVAudio", "AVAsset", "AVURLAsset", "AudioStreamBasicDescription", "AudioBufferList",
            "CGImage", "CGContext", "NSObject", "NSError", "NSURL", "URL", "Process",
            "vDSP", "FFT", "SwiftUI", "View", "Bundle", "FileManager", "URLSession",
        ]

        for file in files {
            let text = try String(contentsOf: ports.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() where isCode(line) {
                for type in forbidden {
                    #expect(
                        line.range(of: "\\b\(type)\\b", options: .regularExpression) == nil,
                        "Ports/\(file):\(index + 1) names \(type): \(line.trimmingCharacters(in: .whitespaces))"
                    )
                }
            }
        }
    }

    /// **The export layer names no visual type.** The structural half of 9.5: a drawing cannot reach
    /// the wire through a parameter that does not exist, and this is where such a parameter would
    /// have to be written.
    @Test("no export source names a visual type")
    func theExportLayerKnowsNoDrawing() throws {
        let export = Self.repositoryRoot.appendingPathComponent("Sources/AudioInspectorApp/Export")
        let files = try FileManager.default.contentsOfDirectory(atPath: export.path)
            .filter { $0.hasSuffix(".swift") }.sorted()
        #expect(!files.isEmpty)

        for file in files {
            let text = try String(contentsOf: export.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() where isCode(line) {
                for type in [
                    "WaveformEnvelope", "WaveformBucket", "Spectrogram", "SpectrogramRaster",
                    "FileVisuals", "PairedVisuals", "SettledWaveform", "SettledSpectrogram",
                    "PCMStreamDescription", "PCMChunk",
                ] {
                    #expect(
                        line.range(of: "\\b\(type)\\b", options: .regularExpression) == nil,
                        "Export/\(file):\(index + 1) names \(type): \(line.trimmingCharacters(in: .whitespaces))"
                    )
                }
            }
        }
    }
}
