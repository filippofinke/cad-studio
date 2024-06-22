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
