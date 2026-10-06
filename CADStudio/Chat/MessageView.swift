import SwiftUI

struct MessageView: View {
    let message: ChatMessage
    let projectRoot: URL
    let perform: (ChatMessage.Action, ChatMessage) -> Void

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .leading, spacing: 8) {
                if let attachments = message.attachments {
                    HStack(spacing: 6) {
                        ForEach(attachments, id: \.self) { path in
                            AttachmentThumbnail(url: projectRoot.appending(path: path), size: 64)
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        case .system:
            SystemMessageView(message: message, perform: perform)
        default:
            MarkdownText(text: message.text)
        }
    }
}

private struct SystemMessageView: View {
    let message: ChatMessage
    let perform: (ChatMessage.Action, ChatMessage) -> Void
    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(LocalizedStringKey(message.text))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: message.detail == nil ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(message.detail == nil ? Color.secondary : Color.orange)
            }
            if let detail = message.detail {
                DisclosureGroup("Dettagli", isExpanded: $showsDetail) {
                    CodeBlock(code: detail)
                }
                .font(.callout)
            }
            if let action = message.action {
                Button(title(for: action)) {
                    perform(action, message)
                }
                .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.25)))
    }

    private func title(for action: ChatMessage.Action) -> LocalizedStringKey {
        switch action {
        case .askClaudeToFix: "Chiedi a Claude di correggere"
        case .openTerminal: "Apri il Terminale"
        case .configureClaude: "Configura Claude Code…"
        }
    }
}

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.isCode {
                    CodeBlock(code: segment.text)
                } else {
                    Text(attributed(segment.text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segments: [(text: String, isCode: Bool)] {
        let parts = text.components(separatedBy: "```")
        return parts.enumerated().compactMap { index, part in
            let isCode = index % 2 == 1
            let content = isCode ? part.drop(while: { $0 != "\n" }).dropFirst() : Substring(part)
            let trimmed = content.trimmingCharacters(in: .newlines)
            return trimmed.isEmpty ? nil : (trimmed, isCode)
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct CodeBlock: View {
    let code: String
    var lineLimit: Int?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 11))
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
                    .lineLimit(lineLimit)
                    .padding(8)
                    .padding(.trailing, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(6)
            .help("Copia")
            .accessibilityLabel(Text("Copia"))
        }
        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 6))
    }
}
