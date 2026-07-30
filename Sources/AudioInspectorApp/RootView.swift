import SwiftUI

/// The root view of the app. Intentionally empty for the scaffolding milestone: it renders an
/// empty window. Real UI (import surface, detail, etc.) arrives with the first vertical slice.
public struct RootView: View {
    public init() {}

    public var body: some View {
        Color.clear
            .frame(minWidth: 720, minHeight: 480)
    }
}
