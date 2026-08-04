import SwiftUI

/// The drop feedback, as a surface the composition root can place over the whole window so it is
/// visible both on the import screen and while a report is shown. The state stays owned by
/// `ImportFlowModel`; this view only renders what it is given, and knows nothing about `URL`s, AppKit
/// or the sandbox.
///
/// **The targeting hint is instructive, never confirmatory.** The macOS 15 drop API reports targeting
/// as a bare `Bool` and does not expose the dragged items until the drop is performed, so the app
/// cannot know whether the content is acceptable beforehand. The overlay therefore states what is
/// expected — never "valid audio" (ADR-0014).
public struct DropFeedbackOverlay: View {
    private let isTargeted: Bool
    private let rejection: DropRejection?

    public init(isTargeted: Bool, rejection: DropRejection?) {
        self.isTargeted = isTargeted
        self.rejection = rejection
    }

    public var body: some View {
        ZStack {
            if isTargeted {
                targetingHint
            } else if let rejection {
                rejectionNotice(rejection)
            }
        }
        .animation(.default, value: isTargeted)
        .allowsHitTesting(false)
    }

    /// Text plus a discreet border. The wording carries the meaning on its own, so the feedback never
    /// depends on colour alone.
    private var targetingHint: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [8]))
                .padding(8)
            Text("Drop one audio file")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityElement()
        .accessibilityLabel("Drop one audio file")
    }

    /// Brief, recoverable, and dismissed by the user's next valid interaction rather than by a timer.
    private func rejectionNotice(_ rejection: DropRejection) -> some View {
        VStack {
            Spacer()
            Text(rejection.message)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 64)
                .accessibilityLabel(rejection.message)
        }
    }
}
