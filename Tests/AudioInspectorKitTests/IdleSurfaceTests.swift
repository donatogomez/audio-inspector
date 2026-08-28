import Foundation
import Testing

@testable import FeatureImport

// R2's third subject: **what the surface says before anything has been chosen**, and in what order.
//
// The claim is about a rendering, so the evidence is read off the source — the shape
// `WorkspaceOwnershipTests`, `SharedPCMDecodeCountTests` and `ImportFlowCopyTests` already use. It is
// deliberately *relative*: no line number is written down, so the assertions survive any edit that does
// not change what the surface says or the order it says it in.

@Suite("Feature — the surface before anything is chosen")
struct IdleSurfaceTests {

    // MARK: - Reading the surface's source

    private static var surface: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureImport/ImportFlowView.swift")
    }

    /// The surface's non-comment lines. Comments are skipped for the reason they always are here: the
    /// records explaining *why* a sentence sits where it does quote the sentences themselves.
    private func code() throws -> [String] {
        try String(contentsOf: Self.surface, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
    }

    /// Where each of the four sentences is referenced, in source order.
    private func positions(of value: String, in code: [String]) -> [Int] {
        code.indices.filter { code[$0].contains("ImportFlowCopy.\(value)") }
    }

    /// The four the frame renders, in the order the capability requires them.
    private static let frame = ["purpose", "chooseFile", "dragAlternative", "readOnlyGuarantee"]

    // MARK: - 3.1 — each rendered once

    @Test("each of the four sentences is rendered exactly once")
    func eachSentenceIsRenderedOnce() throws {
        let code = try code()
        for value in Self.frame {
            let found = positions(of: value, in: code)
            #expect(found.count == 1, "ImportFlowCopy.\(value) is rendered \(found.count) times, not once")
        }
    }

    /// **The order is the contract, not the presence.** Four sentences in the wrong order read as a
    /// different surface: the guarantee before the action reads as a warning, and the alternative before
    /// the action reads as the primary way in.
    @Test("the four are rendered in reading order: purpose, action, alternative, guarantee")
    func theFourAreInReadingOrder() throws {
        let code = try code()
        let found = try Self.frame.map { value -> Int in
            let positions = positions(of: value, in: code)
            #expect(positions.count == 1)
            return try #require(positions.first)
        }
        #expect(found == found.sorted(), "the frame's sentences are out of order: \(Self.frame) at \(found)")
        #expect(Set(found).count == found.count, "two sentences are rendered on the same line")
    }

    /// The guarantee is **last**, and it is the last thing the frame says in every state — never pushed
    /// below the varying region, never conditional on one (`design.md` §5).
    @Test("the guarantee is the last thing the frame says")
    func theGuaranteeIsLast() throws {
        let code = try code()
        let guarantee = try #require(positions(of: "readOnlyGuarantee", in: code).first)
        for other in Self.frame where other != "readOnlyGuarantee" {
            let position = try #require(positions(of: other, in: code).first)
            #expect(position < guarantee, "\(other) is rendered after the guarantee")
        }
    }

    // MARK: - 3.2 — exactly one action

    /// **One control, and dragging is not a second one.** A surface with two equal ways in has no
    /// primary action, and a person using the keyboard alone must be able to do everything it offers —
    /// which a drop target cannot give them.
    @Test("the surface offers exactly one action")
    func thereIsExactlyOneAction() throws {
        let code = try code()
        let buttons = code.filter { $0.contains("Button(") }
        #expect(buttons.count == 1, "the surface offers \(buttons.count) buttons: \(buttons)")

        for control in ["Link(", "Menu(", "NavigationLink(", "Toggle(", "DisclosureGroup(",
                        "onTapGesture", "help("] {
            let found = code.filter { $0.contains(control) }
            #expect(found.isEmpty, "the surface offers a second way in via \(control): \(found)")
        }
    }

    /// The alternative is **stated**, not offered as a control: it is a `Text`, and the line that renders
    /// it carries no action.
    @Test("the drag-and-drop alternative is a sentence, not a control")
    func theAlternativeIsNotAControl() throws {
        let code = try code()
        let line = try #require(code.first { $0.contains("ImportFlowCopy.dragAlternative") })
        #expect(line.contains("Text("), "the alternative is not rendered as text: \(line)")
        for control in ["Button", "Link", "onTapGesture", "Menu"] {
            #expect(!line.contains(control), "the alternative became a control: \(line)")
        }
    }

    /// The guarantee is **plainly visible**: a sentence in the frame, not something a person has to hover
    /// over, open, or scroll to find.
    @Test("the guarantee is stated outright, not hidden behind an interaction")
    func theGuaranteeIsNotHidden() throws {
        let code = try code()
        let line = try #require(code.first { $0.contains("ImportFlowCopy.readOnlyGuarantee") })
        #expect(line.contains("Text("))
        for hiding in ["help(", "DisclosureGroup", "popover", "Menu", "hover", "tooltip"] {
            #expect(!line.contains(hiding), "the guarantee is hidden behind \(hiding): \(line)")
        }
        // And it is not conditional: the frame renders it for every state, so no branch guards this line.
        #expect(!line.contains("if "), "the guarantee is rendered conditionally: \(line)")
    }

    // MARK: - 3.3 — nothing the system cannot do

    /// Capabilities this application does not have. Nothing persists (ADR-0004, ADR-0010), so there is no
    /// history to browse and no library to open; there is no bundled audio and no settings.
    static let absentCapabilities = [
        "history", "recent", "recents", "library", "sample", "samples", "example", "examples",
        "feature", "features", "settings", "preferences", "tutorial", "onboarding", "welcome",
        "tips", "favourite", "favourites", "favorite", "favorites",
    ]

    @Test("the surface promises no capability the system does not have")
    func noAbsentCapabilityIsPromised() throws {
        var strings = ImportFlowCopy.everyRenderableString
        // Plus anything the surface still renders as a literal of its own.
        for line in try code() {
            strings += line.matches(of: /"[^"]*"/).map { String($0.output).trimmingCharacters(in: ["\""]) }
        }
        #expect(strings.count >= 6, "the sweep covered \(strings.count) strings")

        for string in strings {
            for capability in Self.absentCapabilities {
                #expect(
                    string.range(of: "\\b\(capability)\\b", options: [.regularExpression, .caseInsensitive]) == nil,
                    "\"\(string)\" offers \(capability), which this application does not have"
                )
            }
        }
    }

    // MARK: - What belongs to the frame stays out of the region

    /// **The region says what one state has to say, and nothing the frame already says.** The guarantee
    /// in particular must not be repeated there — it belongs to every state, so a copy of it inside the
    /// varying region would be a second home for the product's one trust statement.
    @Test("the varying region renders none of the frame's sentences")
    func theRegionRendersNoFrameContent() throws {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("private func statusRegion") })
        let region = code[start...]
        for value in Self.frame {
            #expect(
                !region.contains { $0.contains("ImportFlowCopy.\(value)") },
                "the region repeats the frame's \(value)"
            )
        }
    }

    /// The two states this group does not touch still say what they said. Their content is the next two
    /// groups' subject, and this asserts the boundary rather than assuming it.
    @Test("the running and failed states keep their own content untouched")
    func theOtherStatesAreUnchanged() throws {
        let code = try code()
        let start = try #require(code.firstIndex { $0.contains("private func statusRegion") })
        let region = Array(code[start...])

        // Running: an indeterminate indicator and nothing else — no status sentence yet.
        #expect(region.contains { $0.contains("ProgressView()") })
        #expect(!region.contains { $0.contains("ImportFlowCopy.inspecting") },
                "the running state gained its sentence early")

        // Failed: the flow's own message, still carried as the associated value.
        #expect(region.contains { $0.contains("Text(message)") })
        #expect(!region.contains { $0.contains("ImportFlowCopy.chooseAnotherFile") },
                "the failure gained its recovery wording early")
    }
}
