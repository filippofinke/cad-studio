import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    let project: Project

    private var chat: ChatViewModel { project.chat }

    var body: some View {
        VStack(spacing: 0) {
            if chat.messages.isEmpty {
                ChatEmptyState { suggestion in
                    project.send(suggestion)
                }
            } else {
                messageList
            }
            ChatInputView(project: project)
        }
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            attach(providers)
            return true
        }
    }

    private func attach(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in chat.attach([url]) }
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let url = Attachments.savedImage(data) else { return }
                    Task { @MainActor in chat.attach([url]) }
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chat.messages) { message in
                        row(for: message)
                            .id(message.id)
                    }
                    if project.isBusy, chat.messages.last?.role == .user {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 2)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(12)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: chat.messages.last) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func row(for message: ChatMessage) -> some View {
        switch message.role {
        case .tool:
            ToolActivityRow(message: message)
        case .thinking:
            ThinkingRow(text: message.text, isActive: message.id == chat.activeThinkingID)
        case .summary where VersionMarker.number(of: message) != nil:
            VersionMarker(project: project, message: message)
        case .summary:
            Text(message.text)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
        default:
            MessageView(message: message, projectRoot: project.folder.root, perform: perform)
        }
    }

    private func perform(_ action: ChatMessage.Action, for message: ChatMessage) {
        switch action {
        case .askClaudeToFix:
            project.askClaudeToFix(message.detail ?? message.text)
        case .openTerminal:
            NSWorkspace.shared.openApplication(
                at: URL(filePath: "/System/Applications/Utilities/Terminal.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        case .configureClaude:
            AgentLocator.current.isMissingSheetPresented = true
        }
    }
}
