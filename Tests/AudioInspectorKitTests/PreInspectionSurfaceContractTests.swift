import Foundation
import Testing

@testable import AudioInspectorApp
@testable import FeatureImport

// R2's closing subject: **what the redesigned surface must not have cost.**
//
// Groups 1-5 built the three states. This is the other half of the slice — the mechanisms it inherited
// and had to leave working, the keyboard and assistive paths it had to leave usable, and the boundaries
// it had to leave where it found them. All of it is read off the sources, in the shape the earlier
// suites established.

@Suite("Feature — what the pre-inspection surface preserved")
struct PreInspectionSurfaceContractTests {

    // MARK: - Reading the sources

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func code(of path: String) throws -> [String] {
        try String(contentsOf: Self.repositoryRoot.appendingPathComponent("Sources/\(path)"), encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
    }

    private func surface() throws -> [String] { try code(of: "FeatureImport/ImportFlowView.swift") }
    private func root() throws -> [String] { try code(of: "AudioInspectorApp/RootView.swift") }

    // MARK: - 6.1 — the destination is the window, in every state

    /// **The whole window takes the drop, and it always did.** The destination is attached to the root,
    /// *outside* the branch that chooses between the pre-report surface and the workspace, so it applies
    /// to every state rather than to whichever one happens to be on screen. Asserted where it is wired,
    /// not argued from a diff.
    @Test("the drop destination is the whole window, above the state it is showing")
    func theDropDestinationIsTheWholeWindow() throws {
        let root = try root()
        let destinations = root.indices.filter { root[$0].contains(".dropDestination(") }
        #expect(destinations.count == 1, "the window has \(destinations.count) drop destinations")

        // It is applied to the root group, after the switch closes — so it is not inside a branch.
        let group = try #require(root.firstIndex { $0.contains("Group {") })
        let switchEnd = try #require(root.firstIndex { $0.contains("reportSurface(presentation)") })
        let destination = try #require(destinations.first)
        #expect(destination > switchEnd, "the drop destination sits inside one state's branch")
        #expect(destination > group)

        // The overlay is on the same root, so the feedback covers the window too.
        let overlay = try #require(root.firstIndex { $0.contains("DropFeedbackOverlay(") })
        #expect(overlay > switchEnd)
    }

    /// The surface renders inside that destination and never takes the drop away from it: it installs no
    /// destination of its own and swallows no clicks.
    @Test("the pre-inspection surface intercepts nothing the window is listening for")
    func theSurfaceInterceptsNothing() throws {
        let surface = try surface()
        for interception in [".dropDestination", ".onDrop", ".contentShape", ".allowsHitTesting",
                            ".onTapGesture", ".gesture("] {
            #expect(
                !surface.contains { $0.contains(interception) },
                "the surface intercepts \(interception), which belongs to the window"
            )
        }
    }

    /// **The alternative is stated, and the mechanism is not narrowed to it.** No box, no zone, no
    /// second target: the sentence tells a person they may drag, and the whole window is what accepts it.
    @Test("the drag-and-drop alternative is a sentence and not a target")
    func theAlternativeIsNotATarget() throws {
        let surface = try surface()
        let line = try #require(surface.first { $0.contains("ImportFlowCopy.dragAlternative") })
        #expect(line.contains("Text("))
        #expect(ImportFlowCopy.dragAlternative == "Or drag one onto this window.")
        // It names the window, because the window is what takes it.
        #expect(ImportFlowCopy.dragAlternative.contains("this window"))
    }

    /// The three refusals keep their exact words and their single home. This slice added none, changed
    /// none, and moved none.
    @Test("the drop's refusals are exactly the three, unchanged")
    func theRefusalsAreUnchanged() throws {
        #expect(DropRejection.allCases.count == 3)
        #expect(DropRejection.multipleItems.message == "Drop one file at a time.")
        #expect(DropRejection.unsupportedItem.message == "That item cannot be inspected.")
        #expect(DropRejection.inspectionInProgress.message == "Wait for the current inspection to finish.")

        // And the pre-inspection surface declares none of them.
        let surface = try surface()
        for rejection in DropRejection.allCases {
            #expect(!surface.contains { $0.contains(rejection.message) })
            #expect(!ImportFlowCopy.everyRenderableString.contains(rejection.message))
        }
    }

    // MARK: - 7.1 — the keyboard reaches everything

    /// **Everything this surface offers is reachable without a pointer.** One action, and it is the
    /// window's default, so Return begins an inspection; dragging is an alternative and never the only
    /// way to do anything.
    @Test("the one action is reachable and invocable from the keyboard alone")
    func theActionIsReachableFromTheKeyboard() throws {
        let surface = try surface()
        #expect(surface.filter { $0.contains("Button(") }.count == 1)
        #expect(surface.contains { $0.contains(".keyboardShortcut(.defaultAction)") })
    }

    /// **Nothing reorders or steals focus.** The reading order is the focus order because nothing
    /// overrides it, and no decorative element is made focusable to sit in the way.
    @Test("focus follows reading order, because nothing rearranges it")
    func focusFollowsReadingOrder() throws {
        let surface = try surface()
        for override in ["FocusState", ".focused(", ".prefersDefaultFocus", ".focusable(",
                         "AccessibilityNotification", ".accessibilityFocused"] {
            #expect(
                !surface.contains { $0.contains(override) },
                "the surface takes control of focus with \(override)"
            )
        }
    }

    // MARK: - 7.2 / 7.3 — meaning is carried in words

    /// Each state's meaning is a sentence, not an animation and not a colour.
    @Test("every state says what it is, in words")
    func everyStateSaysWhatItIsInWords() throws {
        let surface = try surface()
        // Running: the indicator and the sentence are one element, so it is heard as one thing.
        #expect(surface.contains { $0.contains("Text(ImportFlowCopy.inspecting)") })
        #expect(surface.contains { $0.contains(".accessibilityElement(children: .combine)") })
        // Failed: the sentence is the flow's, and the symbol beside it is not announced twice.
        #expect(surface.contains { $0.contains("Text(message)") })
        #expect(surface.contains { $0.contains(".accessibilityHidden(true)") })
        // Idle: the frame's four sentences are the whole of it.
        #expect(surface.contains { $0.contains("Text(ImportFlowCopy.purpose)") })
        #expect(surface.contains { $0.contains("Text(ImportFlowCopy.readOnlyGuarantee)") })
    }

    /// **Colour is never the carrier.** It appears once, on the failure, beside a symbol and a sentence
    /// that both say the same thing without it.
    @Test("nothing on this surface means anything by colour alone")
    func nothingMeansAnythingByColourAlone() throws {
        let surface = try surface()
        let colours = surface.filter {
            $0.contains(".foregroundStyle(.red)") || $0.contains(".foregroundStyle(.orange)")
                || $0.contains(".foregroundStyle(.green)") || $0.contains(".foregroundStyle(.yellow)")
        }
        #expect(colours.count == 1, "colour carries meaning in \(colours.count) places: \(colours)")
        // The one place is the failure, which also has a symbol and the flow's sentence.
        let start = try #require(surface.firstIndex { $0.contains("case let .failed(message):") })
        let region = Array(surface[start...])
        #expect(region.contains { $0.contains(".foregroundStyle(.red)") })
        #expect(region.contains { $0.contains("Image(systemName:") })
        #expect(region.contains { $0.contains("Text(message)") })
    }

    /// Nothing is hidden behind a pointer: no hover, no tooltip, no disclosure anywhere on the surface.
    @Test("no information on this surface requires a pointer to reveal")
    func nothingRequiresAPointer() throws {
        let surface = try surface()
        for hiding in [".help(", "DisclosureGroup", ".popover(", ".onHover", "TabView", ".sheet("] {
            #expect(!surface.contains { $0.contains(hiding) }, "information is hidden behind \(hiding)")
        }
    }

    // MARK: - 8.1 — the surface is not a section

    /// **The pre-report surface is not part of the workspace's navigation**, and the workspace's
    /// navigation is not part of it. R1's own suites hold the other half; this is the half that belongs
    /// to the slice that could have blurred it.
    @Test("the pre-inspection surface is not a section of the workspace")
    func theSurfaceIsNotASection() throws {
        #expect(WorkspaceSection.allCases.count == 5)
        #expect(WorkspaceSection.allCases == [.overview, .measurements, .waveform, .spectrum, .details])
        for section in WorkspaceSection.allCases {
            let label = WorkspaceCopy.label(for: section).lowercased()
            for absent in ["empty", "idle", "working", "inspecting", "failed", "import"] {
                #expect(label != absent, "a section is named for a pre-report state")
            }
        }
        // The navigation is built inside the report surface only, and the pre-report surface never
        // names it.
        let surface = try surface()
        for navigation in ["WorkspaceSection", "WorkspaceNavigation", "sectionNavigation"] {
            #expect(!surface.contains { $0.contains(navigation) })
        }
        let root = try root()
        let navigationSite = try #require(root.firstIndex { $0.contains("private var sectionNavigation") })
        let importSurface = try #require(root.firstIndex { $0.contains("ImportFlowView(model: flow)") })
        #expect(navigationSite > importSurface, "the navigation is built beside the pre-report surface")
    }

    // MARK: - 8.4 — the file-access guarantees are where they were

    /// The panel's configuration, the drop's acceptance rules, and the absence of any retention. Asserted
    /// at the three places they live rather than inferred from the diff.
    @Test("the file-access guarantees are unchanged")
    func theFileAccessGuaranteesAreUnchanged() throws {
        let panel = try code(of: "AudioInspectorApp/Import/SourceSelection.swift")
        #expect(panel.contains { $0.contains("panel.allowedContentTypes = [.audio]") })
        #expect(panel.contains { $0.contains("panel.allowsMultipleSelection = false") })
        #expect(panel.contains { $0.contains("panel.canChooseDirectories = false") })

        let drop = try code(of: "AudioInspectorApp/Import/DroppedSource.swift")
        #expect(drop.contains { $0.contains("return .rejected(.multipleItems)") })
        #expect(drop.contains { $0.contains("conforms(to: .audio)") })
        #expect(drop.contains { $0.contains("values?.isDirectory == true") })

        let coordinator = try code(of: "AudioInspectorApp/Import/SourceInspectionCoordinator.swift")
        #expect(coordinator.contains { $0.contains("url.startAccessingSecurityScopedResource()") })
        #expect(coordinator.contains { $0.contains("url.stopAccessingSecurityScopedResource()") })

        // Nothing anywhere keeps a location past the operation that needed it.
        for module in ["FeatureImport/ImportFlowModel.swift", "FeatureImport/ImportFlowView.swift",
                       "AudioInspectorApp/Import/SourceInspectionCoordinator.swift"] {
            let lines = try code(of: module)
            for retention in ["bookmarkData", "lastURL", "retainedURL", "storedURL", "UserDefaults"] {
                #expect(!lines.contains { $0.contains(retention) }, "\(module) retains a location")
            }
        }
    }

    // MARK: - 8.5 / 8.6 — the export and the read are out of reach

    /// The export is not reachable from a surface that has no report to export, and this slice added no
    /// path to one.
    @Test("the export is unreachable from the pre-inspection surface")
    func theExportIsUnreachable() throws {
        let surface = try surface()
        for exported in ["ReportExportAction", "export", "schemaVersion", "JSONReportExporter",
                         "ReportExportCoordinator"] {
            #expect(!surface.contains { $0.contains(exported) }, "the surface reaches the export: \(exported)")
        }
    }

    /// **This slice reads nothing.** The surface names no decoding, no analysis and no sample: it renders
    /// what the flow already holds, so it can cause neither a read nor a recomputation.
    @Test("the pre-inspection surface causes no read of the audio")
    func theSurfaceReadsNothing() throws {
        let surface = try surface()
        for reading in ["AudioDecoding", "PCMChunk", "decode(", "WaveformEnvelope", "Spectrogram",
                       "sharedAnalyses", "AVFoundation"] {
            #expect(!surface.contains { $0.contains(reading) }, "the surface reaches the read path")
        }
    }
}
