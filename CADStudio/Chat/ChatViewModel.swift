import Foundation

@MainActor
@Observable
final class ChatViewModel {
    private let file: URL
    private(set) var messages: [ChatMessage]
    var draft = ""
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

    func appendText(_ text: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += text
    }

    func setText(_ text: String, of id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    func completeTool(_ toolUseID: String, output: String, failed: Bool) {
        guard let index = messages.lastIndex(where: { $0.tool?.toolUseID == toolUseID }) else { return }
        messages[index].tool?.output = output
        messages[index].tool?.state = failed ? .failed : .succeeded
    }

    func failRunningTools() {
        for index in messages.indices where messages[index].tool?.state == .running {
            messages[index].tool?.state = .failed
        }
    }

    func save() {
        try? ProjectStore.write(messages, to: file)
    }
}
