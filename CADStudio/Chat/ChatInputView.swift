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

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Allega")
        if panel.runModal() == .OK {
            chat.attach(panel.urls)
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if project.isBusy {
            if chat.canSend {
                Button {
                    project.sendDraft()
                } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Aggiungi alla coda"))
                .help("Aggiungi alla coda: partirà al termine (Invio)")
            }
            Button {
                project.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop"))
            .help("Interrompi (⌘.)")
        } else {
            Button {
                project.sendDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(chat.canSend ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!chat.canSend)
            .accessibilityLabel(Text("Invia"))
            .help("Invia (Invio)")
        }
    }
}

struct AttachmentThumbnail: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Group {
            if Attachments.isImage(url), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 3) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: size * 0.5, height: size * 0.5)
                    Text(url.pathExtension.uppercased())
                        .font(.system(size: max(8, size * 0.15), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .help(url.lastPathComponent)
    }
}
