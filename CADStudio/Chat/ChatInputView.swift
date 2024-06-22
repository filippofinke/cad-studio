import SwiftUI
import UniformTypeIdentifiers

struct ChatInputView: View {
    let project: Project
    @FocusState private var isFocused: Bool
    @State private var pasteMonitor: Any?

    private var chat: ChatViewModel { project.chat }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if !project.queue.isEmpty {
                QueueList(project: project)
            }
            if !chat.draftAttachments.isEmpty {
                attachmentStrip
            }
            HStack(alignment: .bottom, spacing: 6) {
                Button {
                    chooseFiles()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Allega immagini o file di riferimento (puoi anche incollarli con ⌘V)")
                .accessibilityLabel(Text("Allega file"))
                TextField(
                    project.isBusy ? "Scrivi il prossimo messaggio: partirà al termine…" : "Descrivi l’oggetto o la modifica…",
                    text: Binding(get: { chat.draft }, set: { chat.draft = $0 }),
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                            chat.draft += "\n"
                        } else {
                            project.sendDraft()
                        }
                        return .handled
                    }
                sendButton
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor))
            )
            .padding(10)
        }
        .onChange(of: chat.inputFocusRequest) {
            isFocused = true
        }
        .onAppear {
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard isFocused,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers == "v"
                else { return event }
                let urls = Attachments.urls(from: .general)
                guard !urls.isEmpty else { return event }
                chat.attach(urls)
                return nil
            }
        }
        .onDisappear {
            if let pasteMonitor {
                NSEvent.removeMonitor(pasteMonitor)
            }
            pasteMonitor = nil
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chat.draftAttachments, id: \.self) { url in
                    ZStack(alignment: .topTrailing) {
                        AttachmentThumbnail(url: url, size: 52)
                        Button {
                            chat.detach(url)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                        .accessibilityLabel(Text("Rimuovi"))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }
