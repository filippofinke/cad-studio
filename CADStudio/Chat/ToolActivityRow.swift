import SwiftUI

struct ToolActivityRow: View {
    let message: ChatMessage
    @State private var isExpanded = false
    @State private var showsFullOutput = false

    private static let outputPreviewLength = 1500

    private var tool: ToolActivity? { message.tool }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let tool {
                VStack(alignment: .leading, spacing: 6) {
                    CodeBlock(code: tool.input, lineLimit: 12)
                    if let output = tool.output, !output.isEmpty {
                        CodeBlock(code: shownOutput(output))
                        if output.count > Self.outputPreviewLength, !showsFullOutput {
                            Button("Mostra tutto") {
                                showsFullOutput = true
                            }
                            .buttonStyle(.link)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.top, 4)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(message.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.numericText())
                    Spacer(minLength: 4)
                    stateIcon
                }
                if let preview = tool?.preview, !preview.isEmpty, tool?.state == .running {
                    Text(preview)
                        .font(.system(size: 10.5))
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 22)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: tool?.preview)
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.toggle()
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(message.text), \(stateDescription)"))
    }

    private func shownOutput(_ output: String) -> String {
        guard !showsFullOutput, output.count > Self.outputPreviewLength else { return output }
        return String(output.prefix(Self.outputPreviewLength)) + "\n…"
    }

    private var icon: String {
        switch tool?.name {
        case "Bash": "terminal"
        case "Write": "doc.badge.plus"
        case "Edit", "MultiEdit": "pencil"
        case "Read", "Grep", "Glob": "doc.text.magnifyingglass"
        case "TodoWrite": "checklist"
        default: "wrench.and.screwdriver"
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch tool?.state {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
        case .failed, nil:
            Image(systemName: "xmark")
                .foregroundStyle(.red)
        }
    }

    private var stateDescription: String {
        switch tool?.state {
        case .running: String(localized: "in corso")
        case .succeeded: String(localized: "completato")
        case .failed, nil: String(localized: "non riuscito")
        }
    }
}
