import AudioInspectorApp
import SwiftUI

/// The macOS app entry point. A thin `@main` shell over the `AudioInspectorApp` library's
/// composition root. It only presents the (currently empty) root window — no product logic.
///
/// Named `AudioInspectorMainApp` to avoid colliding with the `AudioInspectorApp` module.
@main
struct AudioInspectorMainApp: App {
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            container.makeRootView()
        }
    }
}
