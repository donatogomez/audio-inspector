import SwiftUI

// `ReportSection` was declared inside `ReportView.swift` while that page *was* the report. Every
// workspace section now uses it — Overview, Comparison Overview, Details and Measurements — and the page
// itself is gone, so it lives in a file of its own rather than dying with the surface it was born in.

/// A titled block of the report. Replaces `Form` + `.formStyle(.grouped)`, whose grouped-inset look is
/// the idiom of a Preferences pane rather than of a document being examined.
struct ReportSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// One technical-property row: name, value, the state in words when it is not simply measured, and a
/// reason or exact figure as detail.
