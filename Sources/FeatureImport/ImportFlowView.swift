import SwiftUI

/// The import surface: the starting screen, the in-progress feedback, and the recoverable error
/// state. It renders **only** the states in which no report is available — presenting a report is
/// `FeatureAnalysis`'s job, and the composition root switches between the two.
///
/// Depends on the domain and SwiftUI only: no AppKit, no `URL`, no filesystem.
public struct ImportFlowView: View {
    private let model: ImportFlowModel

    public init(model: ImportFlowModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("Audio Inspector")
                .font(.title2)
            Text("Choose a local audio file — or drag one onto this window — to inspect its technical properties. The file is only read, never modified, moved or copied.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if case let .failed(message) = model.state {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button(hasFailed ? "Try again" : "Choose audio file…") {
                Task { await model.selectAndInspect() }
            }
            .disabled(model.state == .working)

            if model.state == .working {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasFailed: Bool {
        if case .failed = model.state { return true }
        return false
    }
}
