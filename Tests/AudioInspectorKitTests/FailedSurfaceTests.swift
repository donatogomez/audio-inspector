import Foundation
import Testing

@testable import FeatureImport

// R2's fifth subject: **what the surface says when no inspection could be started, and what it offers a
// person to do about it.**
//
// Two questions, and the answers have to be honest: what happened comes from the flow untouched, and
// what to do now is named for what it actually does. Nothing about the failed selection is retained —
// no URL, no bookmark (ADR-0010, ADR-0013) — so there is nothing to try again.

@Suite("Feature — the surface when an inspection could not be started")
struct FailedSurfaceTests {

    // MARK: - Reading the surface's source

    private static var featureImport: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureImport")
    }

    private func code(of file: String) throws -> [String] {
        try String(contentsOf: Self.featureImport.appendingPathComponent(file), encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
    }

    private func surface() throws -> [String] { try code(of: "ImportFlowView.swift") }

    /// The lines the failed state renders, and only those.
    ///
    /// It is the switch's last case, so the branch runs to the end of the file — which is what keeps the
    /// modifiers applied *after* a container inside the region rather than outside it.
    private func failedRegion() throws -> [String] {
        let code = try surface()
        let start = try #require(code.firstIndex { $0.contains("case let .failed(message):") })
        let region = Array(code[(start + 1)...])
        #expect(!region.isEmpty, "the failed state renders nothing")
        return region
    }

    // MARK: - 5.1 — the flow's own sentence, unaltered

    /// **The message is the associated value, not a constant.** The surface renders what the operation
    /// produced; a sentence of its own here would be a second home for one fact.
    @Test("the failure shows the flow's own message, carried through untouched")
    func theMessageIsTheFlowsOwn() throws {
        let region = try failedRegion()
        #expect(region.contains { $0.contains("Text(message)") }, "the failure does not show the message")

        // Nothing wraps, prefixes or summarises it.
        for rewriting in ["Text(\"", "\\(message)", "message.", "String(format"] {
            #expect(
                !region.contains { $0.contains(rewriting) },
                "the message is rewritten rather than presented: \(rewriting)"
            )
        }
        // And the copy owner does not restate it — one fact, one home.
        #expect(!ImportFlowCopy.everyRenderableString.contains { $0.contains("could not be opened") })
    }

    /// **Red is no longer the only thing that marks it.** A symbol carries the distinction by shape; the
    /// sentence beside it carries the meaning in words, which is why the symbol is hidden from assistive
    /// readers rather than announced twice.
    @Test("the failure is marked by more than colour")
    func theFailureDoesNotDependOnColour() throws {
        let region = try failedRegion()
        #expect(
            region.contains { $0.contains("Image(systemName:") },
            "the failure is distinguished by colour alone"
        )
        #expect(
            region.contains { $0.contains("accessibilityHidden(true)") },
            "the symbol is announced as well as the sentence, which says the same thing twice"
        )
        // The colour stays, as reinforcement rather than as the carrier.
        #expect(region.contains { $0.contains("foregroundStyle(.red)") })
    }

    // MARK: - 5.2 — a way forward, named for what it does

    @Test("the way forward is named for choosing a file")
    func theRecoveryActionIsNamedForWhatItDoes() throws {
        let code = try surface()
        let rendered = code.filter { $0.contains("ImportFlowCopy.chooseAnotherFile") }
        #expect(rendered.count == 1, "the recovery wording appears \(rendered.count) times")
        #expect(ImportFlowCopy.chooseAnotherFile == "Choose another file…")

        // It is the label of the one action, decided by a total switch over the states.
        #expect(code.contains { $0.contains("case .failed: ImportFlowCopy.chooseAnotherFile") })
        #expect(code.contains { $0.contains("Button(actionLabel(for: presentation))") })
    }

    /// **The way forward is usable.** A failure that shows a disabled action is a dead end with a
    /// button on it.
    @Test("the way forward is available while the failure is shown")
    func theRecoveryActionIsAvailable() throws {
        #expect(PreInspectionPresentation.failed(message: "x").isInspecting == false)
        let code = try surface()
        #expect(code.contains { $0.contains(".disabled(presentation.isInspecting)") })
        // Nothing else disables it, and nothing hides it in one state.
        let disablers = code.filter { $0.contains(".disabled(") }
        #expect(disablers.count == 1, "the action is disabled from \(disablers.count) places")
        let region = try failedRegion()
        #expect(!region.contains { $0.contains("Button(") }, "the action moved into the failure's region")

        // **And it is rendered unconditionally.** Disabling is not the only way to make a dead end:
        // hiding the action would leave a failure with no way out and every assertion above still true,
        // so the frame is required to carry no branch at all. Only the region varies.
        let start = try #require(code.firstIndex { $0.contains("private func shell(") })
        let end = try #require(code.firstIndex { $0.contains("private func actionLabel(") })
        let frame = Array(code[start ..< end])
        #expect(!frame.isEmpty)
        let branches = frame.filter {
            $0.range(of: "^\\s*(if|guard|switch) ", options: .regularExpression) != nil
        }
        #expect(branches.isEmpty, "the frame renders conditionally, so an element can vanish: \(branches)")
    }

    /// **The same action as idle's, and only the word differs.** Pressing it opens the file chooser; it
    /// does not repeat anything, because nothing was kept to repeat.
    @Test("the way forward opens a new selection rather than repeating the last one")
    func theRecoveryActionStartsAFreshSelection() throws {
        let view = try surface()
        let invocations = view.filter { $0.contains("model.selectAndInspect()") }
        #expect(invocations.count == 1, "the surface has \(invocations.count) ways to start an inspection")

        // The flow offers nothing that could repeat a selection, so no control could call one.
        let model = try code(of: "ImportFlowModel.swift")
        for repetition in ["func retry", "func repeatInspection", "func rerun", "lastURL", "lastSource",
                           "bookmarkData", "retainedURL"] {
            #expect(!model.contains { $0.contains(repetition) }, "the flow now offers \(repetition)")
        }
    }

    @Test("the surface offers exactly one action while the failure is shown")
    func thereIsStillExactlyOneAction() throws {
        let code = try surface()
        #expect(code.filter { $0.contains("Button(") }.count == 1)
        for extra in ["Link(", "Menu(", "NavigationLink(", "DisclosureGroup(", "onTapGesture", "help("] {
            #expect(!code.contains { $0.contains(extra) }, "the failure offers a second way out: \(extra)")
        }
    }

    // MARK: - 5.3 — nothing claims to repeat the selection

    /// Wording that would name something the system cannot do. Nothing about the failed selection is
    /// retained, so *try again* has nothing to try.
    static let repetition = ["try again", "retry", "repeat", "run again", "rerun", "again",
                             "reattempt", "once more", "same file"]

    @Test("no wording on the surface claims to repeat the failed selection")
    func nothingClaimsToRepeat() throws {
        var strings = ImportFlowCopy.everyRenderableString
        for line in try surface() {
            strings += line.matches(of: /"[^"]*"/).map { String($0.output).trimmingCharacters(in: ["\""]) }
        }
        #expect(strings.count >= 6)
        for string in strings {
            for term in Self.repetition {
                #expect(
                    string.range(of: term, options: [.caseInsensitive]) == nil,
                    "\"\(string)\" claims to \(term), and nothing about the failed selection is kept"
                )
            }
        }
    }

    // MARK: - 5.4 — a failure is not a report

    /// **Two different things the flow already distinguishes.** A file that cannot be opened at all
    /// becomes `.failed` and belongs to this surface; a file that opens but cannot be read becomes a
    /// **report** whose status is failed, and belongs to the workspace.
    @Test("a globally failed report is a report, and never reaches this surface")
    func aFailedReportIsNotThisSurface() throws {
        // The projection refuses it — the structural half, asserted here so this slice cannot blur it.
        let code = try code(of: "PreInspectionPresentation.swift")
        #expect(code.contains { $0.contains("case .report: return nil") })

        // And the surface names nothing belonging to a report or to the workspace's navigation.
        let surface = try surface()
        // Matched on word boundaries: `PreInspectionPresentation` is this surface's own projection and
        // merely contains one of these names as a substring.
        for reported in ["InspectionPresentation", "InspectionReport", "ReportView", "WorkspaceSection",
                         "WorkspaceNavigation", "ReportVisuals", "ComparisonPresentation"] {
            let offenders = surface.filter {
                $0.range(of: "\\b\(reported)\\b", options: .regularExpression) != nil
            }
            #expect(
                offenders.isEmpty,
                "the pre-report surface names \(reported), which belongs to a report: \(offenders)"
            )
        }
    }

    /// The failure is not dressed as an outcome: no status, no verdict, no code, no export.
    @Test("the failure is not presented as a result")
    func theFailureIsNotAResult() throws {
        let region = try failedRegion()
        for outcome in ["status", "result", "verdict", "conclusion", "code", "export", "detail"] {
            #expect(
                !region.contains { $0.localizedCaseInsensitiveContains(outcome) },
                "the failure is presented as a \(outcome)"
            )
        }
    }

    // MARK: - What the failure must not disturb

    /// The frame is shared, so the guarantee is on screen while a failure is too — the moment a person
    /// most needs to know their file was not touched.
    @Test("the guarantee is on screen while a failure is shown")
    func theGuaranteeSurvivesTheFailure() throws {
        let code = try surface()
        let region = try failedRegion()
        #expect(code.contains { $0.contains("Text(ImportFlowCopy.readOnlyGuarantee)") })
        #expect(!region.contains { $0.contains("readOnlyGuarantee") })
        #expect(ImportFlowCopy.readOnlyGuarantee == "The file is only read, never modified, moved or copied.")
    }

    /// The other two states keep their own labels: the word changes, the action does not.
    @Test("idle and working still name the action for choosing a file")
    func theOtherStatesKeepTheirLabel() throws {
        let code = try surface()
        #expect(code.contains { $0.contains("case .idle, .working: ImportFlowCopy.chooseFile") })
        #expect(ImportFlowCopy.chooseFile == "Choose audio file…")

        // The recovery wording belongs to the failed state alone.
        let label = try #require(code.first { $0.contains("case .failed: ImportFlowCopy.chooseAnotherFile") })
        #expect(!label.contains("idle") && !label.contains("working"))
    }
}
