import Foundation

@MainActor
@Observable
final class ChatViewModel {
    private let file: URL
    private(set) var messages: [ChatMessage]
    var draft = ""
    var activeThinkingID: UUID?
    private(set) var draftAttachments: [URL] = []
    private(set) var inputFocusRequest = UUID()

    init(file: URL) {
        self.file = file
        messages = (try? ProjectStore.read([ChatMessage].self, from: file)) ?? []
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftAttachments.isEmpty
    }

    func attach(_ urls: [URL]) {
        draftAttachments += urls.filter { !draftAttachments.contains($0) }
    }

    func detach(_ url: URL) {
        draftAttachments.removeAll { $0 == url }
    }

    func reload() {
        messages = (try? ProjectStore.read([ChatMessage].self, from: file)) ?? []
    }

    func focusInput() {
        inputFocusRequest = UUID()
    }

    func takeDraft() -> (text: String, attachments: [URL])? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftAttachments.isEmpty else { return nil }
        defer {
            draft = ""
            draftAttachments = []
        }
        return (text, draftAttachments)
    }

    @discardableResult
    func append(_ message: ChatMessage) -> UUID {
        messages.append(message)
        return message.id
    }
