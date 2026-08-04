import Foundation
import Testing

/// **Configuration guarantee**, not a dynamic traffic test (task 7.2, network half).
///
/// This suite asserts what the shipped executable is *allowed* to do: it decodes the app's
/// entitlements and checks that App Sandbox is on, that the only file capability is the
/// user-selected one approved in ADR-0013, and that **no network entitlement is declared**. Under App
/// Sandbox a process without `com.apple.security.network.client` cannot open outgoing connections —
/// the restriction is enforced by the operating system, not by our own discipline.
///
/// What this suite deliberately does **not** claim: that no traffic occurs at runtime. `swift test`
/// runs unsandboxed and does not exercise the `.app`, so observing real connections belongs to the
/// manual runbook (`docs/manual-validation-mvp.md`). The complementary static guarantee — no network
/// APIs in production code — is enforced by `Scripts/check-boundaries.sh`.
@Suite("Security — offline configuration guarantee")
struct OfflineConfigurationTests {

    /// The app's entitlements, decoded with `PropertyListDecoder` into a typed shape — no
    /// `NSDictionary`, no heterogeneous casts. Every key is optional so a missing capability decodes
    /// as `nil` rather than failing.
    private struct Entitlements: Decodable {
        let appSandbox: Bool?
        let userSelectedReadWrite: Bool?
        let userSelectedReadOnly: Bool?
        let networkClient: Bool?
        let networkServer: Bool?
        let downloadsReadWrite: Bool?
        let musicReadWrite: Bool?
        let picturesReadWrite: Bool?
        let moviesReadWrite: Bool?

        enum CodingKeys: String, CodingKey {
            case appSandbox = "com.apple.security.app-sandbox"
            case userSelectedReadWrite = "com.apple.security.files.user-selected.read-write"
            case userSelectedReadOnly = "com.apple.security.files.user-selected.read-only"
            case networkClient = "com.apple.security.network.client"
            case networkServer = "com.apple.security.network.server"
            case downloadsReadWrite = "com.apple.security.files.downloads.read-write"
            case musicReadWrite = "com.apple.security.assets.music.read-write"
            case picturesReadWrite = "com.apple.security.assets.pictures.read-write"
            case moviesReadWrite = "com.apple.security.assets.movies.read-write"
        }
    }

    /// Locates the entitlements from this source file, so the test does not depend on the working
    /// directory the suite happens to run from.
    private static var entitlementsURL: URL {
        URL(fileURLWithPath: #filePath)          // Tests/AudioInspectorKitTests/<this file>
            .deletingLastPathComponent()          // Tests/AudioInspectorKitTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repository root
            .appendingPathComponent("App/AudioInspector/AudioInspector.entitlements")
    }

    private func decodedEntitlements() throws -> Entitlements {
        let data = try Data(contentsOf: Self.entitlementsURL)
        return try PropertyListDecoder().decode(Entitlements.self, from: data)
    }

    @Test func theEntitlementsFileExistsAndDecodes() throws {
        #expect(FileManager.default.fileExists(atPath: Self.entitlementsURL.path))
        _ = try decodedEntitlements()
    }

    @Test func appSandboxIsEnabled() throws {
        #expect(try decodedEntitlements().appSandbox == true)
    }

    @Test func theOnlyFileCapabilityIsTheApprovedUserSelectedOne() throws {
        let entitlements = try decodedEntitlements()
        // ADR-0013: read-write covers both the inspected file and the export destination…
        #expect(entitlements.userSelectedReadWrite == true)
        // …and read-only is deliberately not declared alongside it (it would be redundant).
        #expect(entitlements.userSelectedReadOnly == nil)
    }

    @Test func noNetworkEntitlementIsDeclared() throws {
        let entitlements = try decodedEntitlements()
        // Without these, the sandbox denies outgoing/incoming connections at the OS level.
        #expect(entitlements.networkClient == nil)
        #expect(entitlements.networkServer == nil)
    }

    @Test func noBroadFolderOrAssetEntitlementIsDeclared() throws {
        let entitlements = try decodedEntitlements()
        #expect(entitlements.downloadsReadWrite == nil)
        #expect(entitlements.musicReadWrite == nil)
        #expect(entitlements.picturesReadWrite == nil)
        #expect(entitlements.moviesReadWrite == nil)
    }
}
