import Foundation
import Testing

@testable import FeatureImport

// R2's first subject: **what the surface before a report is allowed to say**, before any of it is laid
// out.
//
// Everything here is a value, so none of it needs a rendering. The surface itself is rebuilt by this
// change's later groups; what this suite fixes is the vocabulary they will build from, and the one
// sentence that had no protection at all until now.

@Suite("Feature — what the pre-inspection surface says")
struct ImportFlowCopyTests {

    // MARK: - The six sentences, each pinned to itself

    /// **The trust guarantee, verbatim.**
    ///
    /// Asserted as the whole sentence rather than by a substring, because a substring check passes on
    /// *"The file is only read."* — which drops *never modified, moved or copied*, the half that answers
    /// what a person actually worries about. Weakening it must fail here, not only deleting it.
    @Test("the read-only guarantee is exactly the sentence the product promises")
    func theReadOnlyGuaranteeIsVerbatim() {
        #expect(ImportFlowCopy.readOnlyGuarantee == "The file is only read, never modified, moved or copied.")
    }

    @Test("the purpose names what the application does, and promises nothing about results")
    func thePurposeIsExact() {
        #expect(ImportFlowCopy.purpose == "Inspect a local audio file's technical properties.")
    }

    @Test("the primary action is the one the panel already answers to")
    func thePrimaryActionIsExact() {
        #expect(ImportFlowCopy.chooseFile == "Choose audio file…")
    }

    @Test("the drag alternative is stated once, as an alternative")
    func theDragAlternativeIsExact() {
        #expect(ImportFlowCopy.dragAlternative == "Or drag one onto this window.")
    }

    @Test("the running state names the operation and nothing else")
    func theRunningStatusIsExact() {
        #expect(ImportFlowCopy.inspecting == "Inspecting…")
    }

    /// The way out of a failure is named for what it does. **Never *Try again***: nothing about the
    /// failed selection is retained, so there is nothing to try again.
    @Test("the way out of a failure is named for choosing a file, not for retrying one")
    func theRecoveryActionIsExact() {
        #expect(ImportFlowCopy.chooseAnotherFile == "Choose another file…")
        for retry in ["try again", "retry", "repeat", "run again", "again"] {
            #expect(
                !ImportFlowCopy.chooseAnotherFile.lowercased().contains(retry),
                "the recovery action claims to \(retry) a selection the system does not retain"
            )
        }
    }

    // MARK: - The surface as a whole

    @Test("the surface's vocabulary is six distinct, non-empty sentences")
    func theVocabularyIsWhatItSaysItIs() {
        let strings = ImportFlowCopy.everyRenderableString
        #expect(strings.count == 6)
        #expect(Set(strings).count == strings.count, "two of the surface's sentences are the same string")
        for string in strings {
            #expect(!string.isEmpty)
            #expect(string.trimmingCharacters(in: .whitespaces) == string)
        }
        // Every declared sentence is in the list; a value that is not swept is a value that is not
        // protected.
        for declared in [ImportFlowCopy.purpose, ImportFlowCopy.chooseFile, ImportFlowCopy.dragAlternative,
                         ImportFlowCopy.readOnlyGuarantee, ImportFlowCopy.inspecting,
                         ImportFlowCopy.chooseAnotherFile] {
            #expect(strings.contains(declared), "\"\(declared)\" is declared but never swept")
        }
    }

    // MARK: - No quantity, because production has none to report

    /// The words a claimed quantity would arrive in, plus any digit at all — a percentage, a fraction, a
    /// count, a step or a time is a number before it is anything else.
    static let quantityTerms = [
        "percent", "percentage", "fraction", "step", "stage", "phase", "remaining", "elapsed",
        "estimated", "second", "seconds", "minute", "minutes", "complete", "completed",
    ]

    @Test("no sentence this surface can say states a quantity")
    func theSurfaceStatesNoQuantity() {
        for string in ImportFlowCopy.everyRenderableString {
            #expect(
                string.rangeOfCharacter(from: .decimalDigits) == nil,
                "\"\(string)\" states a number, and a progress figure is a number"
            )
            #expect(!string.contains("%"), "\"\(string)\" states a percentage")
            for term in Self.quantityTerms {
                #expect(
                    string.range(of: "\\b\(term)\\b", options: [.regularExpression, .caseInsensitive]) == nil,
                    "\"\(string)\" uses \(term), which claims progress the read path does not report"
                )
            }
        }
    }

    // MARK: - Reading the sources

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/AudioInspectorKitTests/<this file>
            .deletingLastPathComponent()      // Tests/AudioInspectorKitTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repository root
    }

    /// Every `.swift` file under `Sources/`, as (path relative to `Sources/`, lines).
    private func productionFiles() throws -> [(path: String, lines: [String])] {
        let root = Self.repositoryRoot.appendingPathComponent("Sources")
        let paths = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        #expect(paths.count > 20, "no production sources were scanned, so nothing here proved anything")
        return try paths.map { path in
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            return (path, text.components(separatedBy: .newlines))
        }
    }

    /// A line that is not a comment — the same set `ArchitectureBoundaryTests` and the boundary script
    /// skip, and for the same reason: the records explaining at length *why* a sentence lives where it
    /// does must stay readable.
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

    // MARK: - Where the guarantee lives, so the surface has one sentence to consume

    /// **The guarantee belongs to presentation, and to one module of it.**
    ///
    /// The surface that will render it is rebuilt by a later group; what is fixed now is that there is
    /// exactly one sentence for it to render and that no layer below presentation names it. A guarantee
    /// duplicated into the domain, the flow's state or the exported document would be a second place for
    /// it to be edited, and the export is not where a person reads a promise about their file.
    @Test("the read-only guarantee lives in presentation, and nowhere below it")
    func theGuaranteeLivesInPresentation() throws {
        let sentence = ImportFlowCopy.readOnlyGuarantee
        let bearers = try codeLines()
            .filter { $0.line.contains(sentence) }
            .map(\.location)

        #expect(!bearers.isEmpty, "the guarantee is in no production source at all")
        // It is declared where the surface's words live.
        #expect(
            bearers.contains { $0.hasPrefix("FeatureImport/ImportFlowCopy.swift:") },
            "the guarantee is not declared by the surface's copy owner: \(bearers)"
        )
        // And nothing outside this feature module names it — not the domain, not the analysis or media
        // adapters, not the composition root, and not the export.
        let strays = bearers.filter { !$0.hasPrefix("FeatureImport/") }
        #expect(strays.isEmpty, "the guarantee reached a layer that should not carry it: \(strays)")
        // Least of all the flow itself, which owns states and not sentences about them.
        #expect(!bearers.contains { $0.hasPrefix("FeatureImport/ImportFlowModel.swift:") })
    }

    // MARK: - What this copy owner must not take over

    /// **The failure keeps its own sentence.** `ImportFlowModel` produces it and the surface presents it;
    /// restating it here would give one fact two homes and let them drift apart silently.
    @Test("the flow's failure sentence is presented, never restated")
    func theFailureSentenceIsNotRestated() throws {
        let sentence = "That file could not be opened for inspection."
        let bearers = try codeLines().filter { $0.line.contains(sentence) }.map(\.location)

        #expect(bearers.count == 1, "the failure sentence has more than one home: \(bearers)")
        #expect(
            bearers.allSatisfy { $0.hasPrefix("FeatureImport/ImportFlowModel.swift:") },
            "the failure sentence left the flow that produces it: \(bearers)"
        )
        #expect(!ImportFlowCopy.everyRenderableString.contains { $0.contains(sentence) })
    }

    /// **The drop's sentences keep their single home.** Three belong to `DropRejection` and one to
    /// `DropFeedbackOverlay`; this surface's copy owner declares none of them.
    @Test("the drop's own sentences are not redeclared by this surface")
    func theDropSentencesAreNotRedeclared() throws {
        let homes = [
            "Drop one file at a time.": "FeatureImport/DropRejection.swift",
            "That item cannot be inspected.": "FeatureImport/DropRejection.swift",
            "Wait for the current inspection to finish.": "FeatureImport/DropRejection.swift",
            "Drop one audio file": "FeatureImport/DropFeedbackOverlay.swift",
        ]
        let lines = try codeLines()
        for (sentence, home) in homes {
            let bearers = lines.filter { $0.line.contains(sentence) }.map(\.location)
            #expect(!bearers.isEmpty, "\"\(sentence)\" is in no production source")
            #expect(
                bearers.allSatisfy { $0.hasPrefix("\(home):") },
                "\"\(sentence)\" left \(home): \(bearers)"
            )
            #expect(!ImportFlowCopy.everyRenderableString.contains { $0.contains(sentence) })
        }
    }

    // MARK: - The same sweep, over the source rather than the values

    /// A quantity added straight into the view would never reach the copy owner, so the sweep reads the
    /// string literals of **this surface's own sources** as well as its values.
    ///
    /// It covers `ImportFlowView` too, which still renders its own literals until the surface is rebuilt;
    /// the file stays in scope afterwards, when those literals are the copy owner's values instead.
    @Test("no string literal in the surface's own sources states a quantity")
    func theSurfacesSourcesStateNoQuantity() throws {
        let surface = ["FeatureImport/ImportFlowCopy.swift", "FeatureImport/ImportFlowView.swift"]
        let lines = try codeLines().filter { line in surface.contains { line.location.hasPrefix("\($0):") } }
        #expect(lines.count > 40, "the surface's sources were not scanned: \(lines.count) lines")

        var offenders: [String] = []
        for (location, line) in lines {
            for literal in line.matches(of: /"[^"]*"/).map({ String($0.output) }) {
                if literal.rangeOfCharacter(from: .decimalDigits) != nil || literal.contains("%") {
                    offenders.append("\(location): \(literal) states a number")
                }
                for term in Self.quantityTerms
                where literal.range(of: "\\b\(term)\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                    offenders.append("\(location): \(literal) uses \(term)")
                }
            }
        }
        #expect(offenders.isEmpty, "the surface's sources claim a quantity: \(offenders)")
    }
}
