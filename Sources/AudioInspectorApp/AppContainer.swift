import SwiftUI

/// The application's composition root.
///
/// This is the only place that will wire concrete implementations (media, analysis) to the domain
/// ports and inject them into features. At the scaffolding stage it wires nothing — it just vends
/// an empty root view. Real dependency wiring arrives with the first vertical slice.
@MainActor
public struct AppContainer {
    public init() {}

    /// The app's root view. Empty for now.
    public func makeRootView() -> some View {
        RootView()
    }
}
