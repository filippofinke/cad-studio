import SwiftUI
import UniformTypeIdentifiers

struct ChatInputView: View {
    let project: Project
    @FocusState private var isFocused: Bool

    private var chat: ChatViewModel { project.chat }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if !chat.draftAttachments.isEmpty {
                attachmentStrip
            }
            HStack(alignment: .bottom, spacing: 6) {
                Button {
                    chooseImages()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(project.isBusy)
                .help("Allega immagini di riferimento")
                .accessibilityLabel(Text("Allega immagini"))
                TextField("Descrivi l’oggetto o la modifica…", text: Binding(get: { chat.draft }, set: { chat.draft = $0 }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .disabled(project.isBusy)
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

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Allega")
        if panel.runModal() == .OK {
            chat.attach(panel.urls)
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if project.isBusy {
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
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .help(url.lastPathComponent)
    }
}
