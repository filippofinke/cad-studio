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

private struct ChatEmptyState: View {
    let onSelect: (String) -> Void

    private let suggestions: [String] = [
        String(localized: "Staffa a L 40×40×3 mm con due fori M4"),
        String(localized: "Scatola 60×40×25 mm con coperchio a incastro"),
        String(localized: "Distanziale cilindrico Ø 12 mm, alto 15 mm, con foro M3"),
        String(localized: "Supporto per smartphone inclinato a 60°"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cube.transparent")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Descrivi un oggetto")
                    .font(.title3.weight(.semibold))
                Text("\(AgentEngine.current.name) scrive lo script CAD, genera il modello 3D e la tavola tecnica.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        Label(suggestion, systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
            .frame(maxWidth: 340)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ThinkingRow: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: isActive)
            Text(text)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            if isActive {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .animation(.default, value: text)
        .accessibilityElement(children: .combine)
    }
}

private struct VersionMarker: View {
    let project: Project
    let message: ChatMessage

    static func number(of message: ChatMessage) -> Int? {
        if let detail = message.detail.flatMap(Int.init) {
            return detail
        }
        let words = message.text.split(separator: " ")
        guard words.count == 2, let number = Int(words[1]) else { return nil }
        return number
    }

    private var version: ProjectVersion? {
        let number = Self.number(of: message)
        return project.history.versions.first { $0.number == number }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
            Text(message.text)
                .fontDesign(.monospaced)
            Spacer()
            if let version {
                if project.metadata.currentVersion == version.number {
                    Text("Attuale")
                } else {
                    Button("Ripristina") {
                        project.restore(version)
                    }
                    .buttonStyle(.link)
                    .disabled(project.isBusy)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }
}
