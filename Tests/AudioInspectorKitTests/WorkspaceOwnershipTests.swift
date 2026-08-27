import Foundation
import Testing

@testable import AudioInspectorApp

// R1's third subject: **the boundaries the shell must not cross**, read off the sources rather than
// intended.
//
// This is the shape `SharedPCMDecodeCountTests`' source assertion already uses, and it is here for the
// same reason it is there: behaviour tests pin what the code does, and a source check pins that there is
// no *other* way to do it. ADR-0026's first promotion condition asks for exactly this — "asserted over
// all of `Sources/`, in the shape `SharedPCMDecodeCountTests`' source assertion already uses".
//
// Comment lines are skipped throughout, deliberately: the records that explain at length why the
// selection is not persisted, and why there is no sidebar, must stay readable.

@Suite("App — what the workspace shell may not reach")
struct WorkspaceOwnershipTests {

    // MARK: - Reading the sources

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/AudioInspectorKitTests/<this file>
            .deletingLastPathComponent()      // Tests/AudioInspectorKitTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repository root
    }

    /// Every production `.swift` file — the package's targets **and** the Xcode app shell, because a
    /// section written to disk from `App/` would be just as persisted.
    private func productionFiles() throws -> [(path: String, lines: [String])] {
        var files: [(String, [String])] = []
        for directory in ["Sources", "App"] {
            let root = Self.repositoryRoot.appendingPathComponent(directory)
            let paths = try FileManager.default.subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            for path in paths {
                let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                files.append(("\(directory)/\(path)", text.components(separatedBy: .newlines)))
            }
        }
        #expect(files.count > 20, "no production sources were scanned, so nothing here proved anything")
        return files
    }

    /// A line that is not a comment — the same set `ArchitectureBoundaryTests` and the boundary script
    /// skip.
    private func isCode(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
    }

    /// Every non-comment line of every production file, located so a failure names the offender.
    private func codeLines() throws -> [(location: String, line: String)] {
        try productionFiles().flatMap { file in
            file.lines.enumerated()
                .filter { isCode($0.element) }
                .map { ("\(file.path):\($0.offset + 1)", $0.element) }
        }
    }

    private func mentions(_ term: String, in line: String) -> Bool {
        line.range(of: "\\b\(NSRegularExpression.escapedPattern(for: term))\\b",
                   options: .regularExpression) != nil
    }

    // MARK: - ADR-0026 §4 and promotion condition 1 — ownership

    /// The names the selection is made of. If any of them appears below the composition root, something
    /// under it has learned where the reader is.
    private static let selectionNames = ["WorkspaceSection", "WorkspaceNavigation", "WorkspaceCopy"]

    @Test("no target below the composition root names the selected section")
    func nothingBelowTheCompositionRootNamesTheSelection() throws {
        var offenders: [String] = []
        for (location, line) in try codeLines() where !location.hasPrefix("Sources/AudioInspectorApp/") {
            for name in Self.selectionNames where mentions(name, in: line) {
                offenders.append("\(location): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, "the selected section reached below the composition root: \(offenders)")
    }

    /// The three modules ADR-0026 §4 names, asserted one by one so a failure says which boundary broke
    /// rather than that one did.
    @Test("the domain and the feature modules cannot observe which section is selected")
    func theModulesNamedByTheRecordAreClean() throws {
        let lines = try codeLines()
        for module in ["AudioInspectorDomain", "FeatureImport", "FeatureAnalysis", "AudioInspectorAnalysis",
                       "AudioInspectorMedia"] {
            let offenders = lines
                .filter { $0.location.hasPrefix("Sources/\(module)/") }
                .filter { line in Self.selectionNames.contains { mentions($0, in: line.line) } }
                .map(\.location)
            #expect(offenders.isEmpty, "\(module) names the selected section at \(offenders)")
        }
    }

    /// **The check above is not vacuous.** The composition root does name all three, so a rename that
    /// silently emptied the search would fail here rather than pass everywhere.
    @Test("the composition root is where the selection lives")
    func theCompositionRootNamesTheSelection() throws {
        let lines = try codeLines().filter { $0.location.hasPrefix("Sources/AudioInspectorApp/") }
        for name in Self.selectionNames {
            #expect(
                lines.contains { mentions(name, in: $0.line) },
                "\(name) is named nowhere in the composition root — has it been renamed?"
            )
        }
    }

    // MARK: - ADR-0026 §5 — one lifecycle, and one place the rule is applied

    /// **One call site, so there is one reset.** Two places reading the flow and applying the rule is
    /// how a section comes to move twice, or to move for a reason nobody wrote down.
    @Test("the navigation rule is applied in exactly one place")
    func theRuleHasASingleCallSite() throws {
        let callSites = try codeLines()
            .filter { $0.line.range(of: "\\.observe\\(", options: .regularExpression) != nil }
        #expect(
            callSites.count == 1,
            "the navigation rule is applied in \(callSites.count) places: \(callSites.map(\.location))"
        )
    }

    /// **The rule cannot see a comparison, so a comparison cannot move the reader.** The behavioural
    /// proof is `WorkspaceNavigationLifecycleTests`; this is the structural one, and it is the stronger
    /// of the two because it forbids the input rather than one use of it.
    ///
    /// Scoped to the two files that carry the rule. `WorkspaceCopy` legitimately names the *actions*
    /// that start and close a comparison, which are words on a button and not an input to anything.
    @Test("the section rule takes no comparison as an input")
    func theRuleNamesNoComparison() throws {
        let ruleFiles = [
            "Sources/AudioInspectorApp/Workspace/WorkspaceNavigation.swift",
            "Sources/AudioInspectorApp/Workspace/WorkspaceSection.swift",
        ]
        let lines = try codeLines().filter { ruleFiles.contains($0.location.prefix(while: { $0 != ":" }).description) }
        #expect(!lines.isEmpty, "the rule's own files were not scanned")
        for term in ["comparison", "Comparison", "FileComparison", "MeasurementComparison", "PairedVisuals"] {
            let offenders = lines.filter { $0.line.localizedCaseInsensitiveContains(term) }.map(\.location)
            #expect(offenders.isEmpty, "the section rule names \(term) at \(offenders)")
        }
    }

    // MARK: - ADR-0026 §5 — nothing is persisted

    @Test("no production source persists anything")
    func nothingIsPersisted() throws {
        let stores = ["UserDefaults", "AppStorage", "SceneStorage", "NSUbiquitousKeyValueStore",
                      "NSUserDefaults", "PropertyListEncoder"]
        var offenders: [String] = []
        for (location, line) in try codeLines() {
            for store in stores where mentions(store, in: line) {
                offenders.append("\(location): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, "a production source reaches for a store that survives a launch: \(offenders)")
    }

    /// The selection is not made storable either. A `Codable` section is one line away from a
    /// `UserDefaults` round trip, and the record refuses both.
    @Test("the selection is not encodable")
    func theSelectionIsNotEncodable() throws {
        let workspace = try codeLines().filter { $0.location.hasPrefix("Sources/AudioInspectorApp/Workspace/") }
        #expect(!workspace.isEmpty, "the workspace's own files were not scanned")
        for term in ["Codable", "Encodable", "Decodable", "RawRepresentable"] {
            let offenders = workspace.filter { mentions(term, in: $0.line) }.map(\.location)
            #expect(offenders.isEmpty, "the selection conforms to \(term) at \(offenders)")
        }
    }

    // MARK: - ADR-0026 §12 — no sidebar, and no routes

    /// A sidebar navigates a collection and this app has none, so the type that draws one appears
    /// nowhere. Nor does a stack, a path or a link: five sections are a selection, not a route.
    @Test("there is no sidebar, and no navigation route")
    func thereIsNoSidebarAndNoRoute() throws {
        let types = ["NavigationSplitView", "NavigationStack", "NavigationPath", "NavigationLink",
                     "NavigationView"]
        var offenders: [String] = []
        for (location, line) in try codeLines() {
            for type in types where mentions(type, in: line) {
                offenders.append("\(location): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, "a production source introduces navigation chrome: \(offenders)")
    }

    // MARK: - The fourth requirement — no aggregate over a comparison

    /// The terms the fourth requirement forbids: every way of stating an aggregate over two files, plus
    /// the attribution words ADR-0017 and ADR-0025 refuse. Matched on word boundaries, case-insensitively,
    /// over **this shell's** strings and no others.
    static let forbidden = [
        "same", "identical", "different", "differences", "difference", "differ", "differs",
        "similar", "similarity", "match", "matches", "matching", "score", "rating", "grade",
        "percent", "percentage", "verdict", "confidence", "important", "agree", "agrees",
        "mismatch", "equal", "equivalent", "aggregate", "count", "total", "summary",
        "quality", "better", "worse", "original", "copy", "master", "remaster", "transcode",
        "upsample",
    ]

    private func offendingTerms(in string: String) -> [String] {
        Self.forbidden.filter { term in
            string.range(of: "\\b\(term)\\b", options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// **The shell is a surface that introduces a second file**, so the fourth requirement applies to it
    /// entire — including the state where every comparable measurement agrees, which this surface reaches
    /// by saying nothing about the measurements at all. There is no state-dependent string here: the
    /// shell's words are the same whatever the two files turn out to be, which is why the all-agree case
    /// is covered by sweeping the whole surface rather than by constructing it.
    @Test("no string the shell can render states an aggregate over a comparison")
    func theShellStatesNoAggregate() {
        let strings = WorkspaceCopy.everyRenderableString
        #expect(strings.count == 9, "the sweep covered \(strings.count) strings, not the whole surface")
        for string in strings {
            let offences = offendingTerms(in: string)
            #expect(offences.isEmpty, "\"\(string)\" uses \(offences)")
        }
    }

    /// **A count is a number, so the shell says no numbers.** The cheapest possible refusal of
    /// `"3 differences"`, and the shell has never had a use for a figure.
    @Test("no string the shell can render carries a digit")
    func theShellStatesNoNumber() {
        for string in WorkspaceCopy.everyRenderableString {
            #expect(
                string.rangeOfCharacter(from: .decimalDigits) == nil,
                "\"\(string)\" states a number, and a count is a number"
            )
        }
    }

    /// **The same sweep, over the source rather than the values**, because a count added straight into
    /// the view would never reach `WorkspaceCopy` at all. It reads the string literals of the files the
    /// shell is built from — every place a word can be put on this surface.
    ///
    /// It catches an interpolated count too, since `"\(n) differences"` still carries the literal
    /// *differences*. What it cannot catch is a bare figure with no words around it; that is what the
    /// value sweep above refuses.
    @Test("no string literal in the shell's own sources states an aggregate")
    func theShellsSourcesStateNoAggregate() throws {
        let shell = [
            "Sources/AudioInspectorApp/RootView.swift",
            "Sources/AudioInspectorApp/Workspace/WorkspaceCopy.swift",
            "Sources/AudioInspectorApp/Workspace/WorkspaceNavigation.swift",
            "Sources/AudioInspectorApp/Workspace/WorkspaceSection.swift",
        ]
        let lines = try codeLines().filter { line in
            shell.contains { line.location.hasPrefix("\($0):") }
        }
        #expect(lines.count > 50, "the shell's sources were not scanned: \(lines.count) lines")

        var offenders: [String] = []
        for (location, line) in lines {
            for literal in line.matches(of: /"[^"]*"/).map({ String($0.output) }) {
                let offences = offendingTerms(in: literal)
                if !offences.isEmpty { offenders.append("\(location): \(literal) uses \(offences)") }
            }
        }
        #expect(offenders.isEmpty, "the shell's sources state an aggregate: \(offenders)")
    }
}
