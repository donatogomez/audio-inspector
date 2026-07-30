import Testing

@testable import AudioInspectorAnalysis
@testable import AudioInspectorApp
@testable import AudioInspectorDomain
@testable import AudioInspectorMedia
@testable import AudioInspectorTesting
@testable import FeatureAnalysis
@testable import FeatureImport

/// Scaffolding smoke tests: each target imports, links, and compiles. No functional behavior is
/// asserted — real tests arrive with each vertical slice.
@Suite("Scaffolding — targets link and compile")
struct LinkSmokeTests {
    @Test func domainLinks() {
        _ = AudioInspectorDomain.self
    }

    @Test func analysisLinks() {
        _ = AudioInspectorAnalysis.self
    }

    @Test func mediaLinks() {
        _ = AudioInspectorMedia.self
    }

    @Test func testingSupportLinks() {
        _ = AudioInspectorTesting.self
    }

    @Test func featureImportLinks() {
        _ = FeatureImport.self
    }

    @Test func featureAnalysisLinks() {
        _ = FeatureAnalysis.self
    }

    @MainActor
    @Test func appCompositionRootLinks() {
        _ = AppContainer()
    }
}
