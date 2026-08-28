import Foundation
import Testing

import AudioInspectorDomain
@testable import FeatureImport

// R2's second subject: **the value the surface before a report switches on**, and the structure that
// switches on it.
//
// No SwiftUI and no rendering: what is asserted is the projection, and — where structure is the claim —
// the source, in the shape `WorkspaceOwnershipTests` and `SharedPCMDecodeCountTests` already use.

@MainActor
@Suite("Feature — the surface before a report")
struct PreInspectionPresentationTests {

    // MARK: - Fixtures

    private func report(_ name: String, status: InspectionStatus = .completed) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: 1_024, modifiedAt: nil,
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: TechnicalProperties(sampleRate: .available(44_100)),
            warnings: [],
            status: status
        )
    }

    // MARK: - The three states it represents

    @Test("an idle flow presents the idle surface")
    func idleMapsToIdle() {
        #expect(PreInspectionPresentation(.idle) == .idle)
    }

    @Test("a working flow presents the working surface")
    func workingMapsToWorking() {
        #expect(PreInspectionPresentation(.working) == .working)
    }

    @Test("a failed flow presents the failure")
    func failedMapsToFailed() {
        #expect(
            PreInspectionPresentation(.failed(message: "That file could not be opened for inspection."))
                == .failed(message: "That file could not be opened for inspection.")
        )
    }

    // MARK: - The failure's message is the flow's, unaltered

    /// **Carried through, never restated.** The sentence belongs to the operation that failed, so it
    /// arrives exactly as the flow produced it — not trimmed, not capitalised, not replaced by a
    /// constant of this surface's own.
    @Test("the failure's message arrives exactly as the flow produced it")
    func theFailureMessageIsCarriedThroughUnaltered() {
        for message in [
            "That file could not be opened for inspection.",
            "",
            "  leading and trailing space  ",
            "A sentence with — punctuation, ellipsis… and a 'quote'.",
        ] {
            #expect(PreInspectionPresentation(.failed(message: message)) == .failed(message: message))
        }
    }

    /// The real sentence the flow produces, taken from the flow rather than retyped here, so this cannot
    /// pass against a message production stopped using.
    @Test("the message the real flow produces reaches the surface intact")
    func theRealFailureReachesTheSurface() async {
        let action = ImportFlowModelTests.ScriptedAction(.preparationFailed)
        let model = ImportFlowModel(action: action.run)

        await model.selectAndInspect()

        guard case let .failed(message) = model.state else {
            Issue.record("a preparation failure did not become a flow failure")
            return
        }
        #expect(PreInspectionPresentation(model.state) == .failed(message: message))
        #expect(message == "That file could not be opened for inspection.")
    }

    // MARK: - A report is not an absence of one

    /// **The case this value refuses to have.** Folding a report into `idle` would compile, would look
    /// harmless, and would render a starting screen over a finished inspection.
    @Test("a flow showing a report has no pre-report presentation")
    func aReportIsNotRepresentable() {
        let presentation = InspectionPresentation(report: report("a.wav"), waveform: .loading)
        #expect(PreInspectionPresentation(.report(presentation)) == nil)
    }

    @Test("a report whose status is a global failure is still a report, not this surface's failure")
    func aGloballyFailedReportIsStillAReport() {
        let failed = report(
            "broken.wav",
            status: .failed(InspectionError(code: .fileOpenFailed, message: "could not open"))
        )
        #expect(PreInspectionPresentation(.report(InspectionPresentation(report: failed, waveform: .loading))) == nil)
    }

    // MARK: - Totality, and no impossible state

    /// Every state the flow can hold is answered: three are presented, one is refused, and there is no
    /// fourth answer. The projection has **no default**, so a state added to the flow does not compile
    /// here — the compiler is the primary guard and this is the behavioural half of it.
    @Test("every flow state is answered, and exactly one of them is not this surface's")
    func everyFlowStateIsAnswered() {
        let states: [ImportFlowModel.State] = [
            .idle,
            .working,
            .failed(message: "That file could not be opened for inspection."),
            .report(InspectionPresentation(report: report("a.wav"), waveform: .loading)),
        ]
        let presented = states.compactMap(PreInspectionPresentation.init)
        #expect(presented.count == 3, "a pre-report state lost its presentation, or a report gained one")
        #expect(Set(states.map { PreInspectionPresentation($0) == nil }).count == 2)
    }

    /// The predicate the surface's controls ask, answered by the value and by nothing else — so "is the
    /// action available" cannot come from a second read of the flow.
    ///
    /// **`hasFailed` was retired with the ternary it existed for.** The label is now decided by a total
    /// switch over the three cases, which answers the same question without a boolean and fails to
    /// compile if a fourth state appears; a derived property nothing derives is dead. The invariant it
    /// carried — a surface is never working *and* failed — is a property of the enum and is asserted
    /// below by matching the cases directly.
    @Test("the predicate the controls ask is answered by the state alone")
    func thePredicatesFollowTheState() {
        #expect(PreInspectionPresentation.idle.isInspecting == false)
        #expect(PreInspectionPresentation.working.isInspecting == true)
        #expect(PreInspectionPresentation.failed(message: "x").isInspecting == false)

        // Never both: a surface cannot be working and failed at once, and the type makes that
        // unrepresentable rather than merely unobserved.
        for state in [PreInspectionPresentation.idle, .working, .failed(message: "x")] {
            let failed = if case .failed = state { true } else { false }
            #expect(!(state.isInspecting && failed))
        }
    }

    // MARK: - Reading the sources

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func lines(of file: String) throws -> [(number: Int, text: String)] {
        let url = Self.repositoryRoot.appendingPathComponent("Sources/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.components(separatedBy: .newlines).enumerated()
            .map { ($0.offset + 1, $0.element) }
            .filter { line in
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
    }

    // MARK: - One shell, one region, and no state of its own

    /// **The surface holds nothing.** A stored property on the view would be a second place the state of
    /// this window lives, free to drift from `ImportFlowModel` — which is the failure this whole slice's
    /// shape exists to prevent. The only stored member is the model it projects.
    @Test("the surface stores nothing of its own")
    func theSurfaceHoldsNoStateOfItsOwn() throws {
        let code = try lines(of: "FeatureImport/ImportFlowView.swift")
        var offenders: [String] = []
        for (number, text) in code {
            for marker in ["@State", "@StateObject", "@ObservedObject", "@Observable", "@AppStorage",
                           "@SceneStorage", "@Environment", "@FocusState"] where text.contains(marker) {
                offenders.append("ImportFlowView.swift:\(number): \(text.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, "the surface grew state of its own: \(offenders)")

        let stored = code.filter { $0.text.range(of: "^\\s+(private )?(let|var) ", options: .regularExpression) != nil }
        #expect(
            stored.count == 1,
            "the surface stores more than the model it projects: \(stored.map { "\($0.number): \($0.text)" })"
        )
    }

    /// **One region, not two insertion points.** The states differ in exactly one *place on screen*, and
    /// the frame around it is built by one code path that no state branches around.
    ///
    /// **The count of `switch presentation` was a proxy, and it stopped being an exact one.** A later
    /// group gave the one action a label that varies by state — a word at a fixed position, decided by a
    /// total switch returning `String`. That is not a second region: nothing moves, appears or
    /// disappears. So the assertion now says what it always meant — exactly one branch *that builds
    /// views* — and every other switch on the state is required to return a value rather than a view.
    @Test("the three states differ in exactly one region")
    func thereIsOneStatusRegion() throws {
        let code = try lines(of: "FeatureImport/ImportFlowView.swift")

        let builders = code.filter { $0.text.contains("@ViewBuilder") }
        #expect(builders.count == 1, "the surface has \(builders.count) view-building branches, not one")

        // Every switch on the state either builds that one region, or produces a value for the frame.
        let switches = code.filter { $0.text.contains("switch presentation") }
        #expect(!switches.isEmpty)
        let valueProducing = code.filter {
            $0.text.contains("(for presentation: PreInspectionPresentation) -> ") &&
                !$0.text.contains("-> some View")
        }
        #expect(
            switches.count == builders.count + valueProducing.count,
            "a switch on the state belongs to neither the region nor a value: \(switches.map(\.number))"
        )

        // The frame reads the state only through the projection. Nothing in the surface reaches back
        // into the flow's own state.
        let directReads = code.filter { $0.text.contains("model.state") }
        #expect(
            directReads.count == 1,
            "the surface reads the flow's state \(directReads.count) times instead of projecting it once"
        )
    }

    /// The projection is written out, so a state added to the flow stops the build here.
    @Test("the projection defaults nothing")
    func theProjectionHasNoDefault() throws {
        let code = try lines(of: "FeatureImport/PreInspectionPresentation.swift")
        let defaults = code.filter {
            $0.text.range(of: "^\\s*(@unknown )?default\\s*:", options: .regularExpression) != nil
        }
        #expect(defaults.isEmpty, "the projection defaults a case: \(defaults.map(\.number))")
    }
}
