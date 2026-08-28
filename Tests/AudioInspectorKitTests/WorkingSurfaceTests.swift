import Foundation
import Testing

@testable import FeatureImport

// R2's fourth subject: **what the surface may say while an inspection is running**, which is far less
// than it is tempting to say.
//
// The evidence is read off the source, relatively and scoped to the one region — the shape
// `IdleSurfaceTests` established. The behavioural half is already pinned elsewhere and is not repeated
// here: `ImportFlowModelTests.aSecondSelectionIsIgnoredWhileOneIsInFlight` proves a second selection
// starts nothing, and `ImportFlowDropTests.aDropIsIgnoredWhileAnInspectionIsInFlight` proves a drop
// does not either.

@Suite("Feature — the surface while an inspection is running")
struct WorkingSurfaceTests {

    // MARK: - Reading the surface's source

    private static var surface: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureImport/ImportFlowView.swift")
    }

    private func code() throws -> [String] {
        try String(contentsOf: Self.surface, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
    }

    /// The lines the running state renders, and only those: from its own `case` to the next one.
    private func runningRegion() throws -> [String] {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("case .working:") },
                                 "the running state has no branch in the surface")
        let rest = code[(start + 1)...]
        let end = rest.firstIndex { $0.contains("case let .failed") } ?? rest.endIndex
        let region = Array(rest[..<end])
        #expect(!region.isEmpty, "the running state renders nothing")
        return region
    }

    // MARK: - 4.1 — an indeterminate indicator and a sentence

    @Test("the running state shows an indeterminate indicator")
    func theIndicatorIsIndeterminate() throws {
        let region = try runningRegion()
        #expect(region.contains { $0.contains("ProgressView()") }, "the running state shows no indicator")

        // A determinate indicator would state a fraction the read path does not produce.
        let code = try code()
        #expect(
            !code.contains { $0.contains("ProgressView(value") || $0.contains("ProgressView(timerInterval") },
            "the surface claims a progress figure it does not have"
        )
    }

    /// **The indicator does not stand alone.** An animation on its own leaves the reader to infer what is
    /// happening; the sentence says it.
    @Test("the running state says in words that an inspection is under way")
    func theRunningStateSaysSo() throws {
        let region = try runningRegion()
        #expect(
            region.contains { $0.contains("Text(ImportFlowCopy.inspecting)") },
            "the running state shows an indicator and says nothing"
        )
        #expect(ImportFlowCopy.inspecting == "Inspecting…")
    }

    @Test("the running sentence is rendered exactly once, and only while running")
    func theRunningSentenceBelongsToOneState() throws {
        let code = try code()
        let rendered = code.indices.filter { code[$0].contains("ImportFlowCopy.inspecting") }
        #expect(rendered.count == 1, "the running sentence is rendered \(rendered.count) times")

        // The one place it appears is inside the running branch — not the frame, which every state
        // shares, and not another state's.
        let region = try runningRegion()
        #expect(region.contains { $0.contains("ImportFlowCopy.inspecting") })
    }

    /// The action stays where it was and stops working, rather than disappearing. A control that
    /// vanishes reads as a bug and takes everything below it with it.
    @Test("the primary action is still present, and unavailable")
    func thePrimaryActionIsPresentAndUnavailable() throws {
        let code = try code()
        let buttons = code.filter { $0.contains("Button(") }
        #expect(buttons.count == 1, "the surface offers \(buttons.count) actions while running")
        // It is disabled by the running state itself, not by a second reading of the flow.
        #expect(code.contains { $0.contains(".disabled(presentation.isInspecting)") })
        #expect(PreInspectionPresentation.working.isInspecting)
        // And it lives in the frame, not in the region, so it does not appear and disappear.
        let region = try runningRegion()
        #expect(!region.contains { $0.contains("Button(") }, "the action moved into the varying region")
    }

    // MARK: - 4.2 — it names no file, because there is none to name

    /// **Structural, not incidental.** `working` carries no associated value, so there is nothing for the
    /// surface to name even if it wanted to — and the state begins before the open panel is answered, so
    /// a name would be wrong for part of the time it covers.
    @Test("the running state carries nothing that could name a file")
    func theRunningStateCarriesNoFile() throws {
        // Every running presentation is the same value: it holds no file, no path, no identity.
        #expect(PreInspectionPresentation(.working) == .working)
        #expect(PreInspectionPresentation.working == PreInspectionPresentation.working)

        let declaration = try String(
            contentsOf: Self.surface.deletingLastPathComponent()
                .appendingPathComponent("PreInspectionPresentation.swift"),
            encoding: .utf8
        )
        #expect(
            declaration.contains("\n    case working\n"),
            "the running state gained a payload, and a payload is something to name"
        )
    }

    /// **The region renders no words of its own.** Everything it shows comes from a value, so a file
    /// name, a stage or a figure cannot be slipped in as a literal.
    @Test("the running state renders no string of its own")
    func theRunningStateRendersNoLiteral() throws {
        let region = try runningRegion()
        var literals: [String] = []
        for line in region {
            literals += line.matches(of: /"[^"]*"/).map { String($0.output) }
        }
        #expect(literals.isEmpty, "the running state renders words from nowhere: \(literals)")
    }

    // MARK: - 4.2 / 4.3 — no stage, no quantity, no way to stop it

    /// Stages the flow does not distinguish. `working` is one state from the moment the operation starts
    /// until it settles, so naming a stage would be a claim about something nothing observes.
    static let stages = [
        "selecting", "choosing", "opening", "reading", "decoding", "analyzing", "analysing",
        "measuring", "preparing", "processing", "loading", "scanning", "finishing",
    ]

    /// Ways of claiming an amount, and ways of offering to stop.
    static let quantities = ["percent", "percentage", "fraction", "step", "stage", "phase",
                             "remaining", "elapsed", "estimated", "eta"]
    static let stopping = ["cancel", "stop", "abort", "pause", "halt", "quit"]

    @Test("the surface names no stage, claims no amount, and offers no way to stop")
    func theSurfaceOverclaimsNothing() throws {
        var strings = ImportFlowCopy.everyRenderableString
        for line in try code() {
            strings += line.matches(of: /"[^"]*"/).map { String($0.output).trimmingCharacters(in: ["\""]) }
        }
        #expect(strings.count >= 6)

        for string in strings {
            for term in Self.stages + Self.quantities + Self.stopping {
                #expect(
                    string.range(of: "\\b\(term)\\b", options: [.regularExpression, .caseInsensitive]) == nil,
                    "\"\(string)\" claims \(term), which the system does not know or cannot do"
                )
            }
            #expect(!string.contains("%"), "\"\(string)\" states a percentage")
        }
    }

    /// **There is nothing to cancel, so nothing offers to.** The flow exposes no cancellation and keeps
    /// its task private; the only thing a person can dismiss is the open panel, which ends the selection
    /// and is already neutral. This asserts the absence at its source, so an offer cannot appear before
    /// the capability does.
    @Test("the flow exposes no cancellation for a control to call")
    func thereIsNothingToCancel() throws {
        let model = try String(
            contentsOf: Self.surface.deletingLastPathComponent().appendingPathComponent("ImportFlowModel.swift"),
            encoding: .utf8
        )
        let code = model.components(separatedBy: .newlines).filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
        }
        for offer in ["public func cancel", "public func stop", "public func abort",
                      "public var activeTask", "public private(set) var activeTask"] {
            #expect(!code.contains { $0.contains(offer) }, "the flow now offers \(offer)")
        }
    }

    // MARK: - What the running state must not disturb

    /// The frame is shared, so the guarantee is on screen while an inspection runs too — and it is
    /// rendered outside the region, which is what makes that true for every state at once.
    @Test("the guarantee is on screen while an inspection runs")
    func theGuaranteeSurvivesTheRunningState() throws {
        let code = try code()
        let region = try runningRegion()
        #expect(code.contains { $0.contains("Text(ImportFlowCopy.readOnlyGuarantee)") })
        #expect(
            !region.contains { $0.contains("ImportFlowCopy.readOnlyGuarantee") },
            "the guarantee moved into one state's region and stopped belonging to the others"
        )
    }

    /// The failure keeps its own content: the flow's message, and the label this group does not rename.
    @Test("the failed state is untouched by this group")
    func theFailedStateIsUntouched() throws {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("case let .failed") })
        let region = Array(code[start...])
        #expect(region.contains { $0.contains("Text(message)") })
        #expect(!region.contains { $0.contains("ImportFlowCopy.inspecting") })
        #expect(!region.contains { $0.contains("ImportFlowCopy.chooseAnotherFile") },
                "the failure gained its recovery wording early")
        #expect(code.contains { $0.contains("\"Try again\"") }, "group 5's rename happened early")
    }

    /// Idle stays empty: the sentence belongs to one state, and an empty region contributes nothing.
    @Test("the idle state says nothing about work that is not happening")
    func theIdleStateIsUntouched() throws {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("case .idle:") })
        let rest = code[(start + 1)...]
        let end = try #require(rest.firstIndex { $0.contains("case .working:") })
        let region = Array(rest[..<end])
        #expect(region.contains { $0.contains("EmptyView()") })
        #expect(!region.contains { $0.contains("ImportFlowCopy.inspecting") })
    }
}
