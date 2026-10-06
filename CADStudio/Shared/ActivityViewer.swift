import SwiftUI

struct ActivityViewer: View {
    let project: Project
    @State private var shownIssueKind: Issue.Kind?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cube")
                .foregroundStyle(.secondary)
            Text(project.name)
                .fontWeight(.medium)
                .lineLimit(1)
            Image(systemName: "chevron.compact.right")
                .foregroundStyle(.tertiary)
            statusIcon
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            issueButton(.error, systemImage: "xmark.octagon.fill", color: .red)
            issueButton(.warning, systemImage: "exclamationmark.triangle.fill", color: .yellow)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(minWidth: 320, idealWidth: 480, maxWidth: 560, minHeight: 24, maxHeight: 24)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(project.name), \(statusText)"))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch project.activity {
        case .working:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    private var statusText: String {
        switch project.activity {
        case .idle: String(localized: "Pronto")
        case .working(let detail), .succeeded(let detail), .failed(let detail): detail
        }
    }

    @ViewBuilder
    private func issueButton(_ kind: Issue.Kind, systemImage: String, color: Color) -> some View {
        let issues = project.issues.filter { $0.kind == kind }
        if !issues.isEmpty {
            Button {
                shownIssueKind = kind
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)
                    Text(issues.count, format: .number)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { shownIssueKind == kind },
                set: { if !$0 { shownIssueKind = nil } }
            )) {
                IssueList(issues: issues, systemImage: systemImage, color: color)
            }
        }
    }
}

private struct IssueList: View {
    let issues: [Issue]
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(issues) { issue in
                Label {
                    Text(issue.message)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(width: 360, alignment: .leading)
    }
}
