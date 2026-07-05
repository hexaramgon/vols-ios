//
//  ConversationViewModel.swift
//  Volspire
//
//  Loads + sends messages (text + attachments) for a single conversation,
//  mirroring the web app's `useConvoMessages` hook (get_convo_messages /
//  send_message / send_message_with_attachment / mark_convo_read). Realtime
//  isn't wired on iOS yet, so new messages are picked up by a light poll.
//

import Foundation
import Services

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let isFromMe: Bool
    let createdAt: Date
    let type: String        // "message" | "system" | "collab_request" | …
    let isAttachment: Bool
    let attachmentURL: URL?
    let attachmentType: String?
    let attachmentName: String?
    var pending: Bool = false

    var isSystem: Bool { type == "system" }
    var isImageAttachment: Bool { isAttachment && (attachmentType?.hasPrefix("image") ?? false) }
    var isAudioAttachment: Bool { isAttachment && (attachmentType?.hasPrefix("audio") ?? false) }
}

@Observable
@MainActor
final class ConversationViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, error(String) }

    var messages: [ChatMessage] = []
    var loadingState: LoadState = .idle
    var draft = ""
    var isSending = false
    var attachmentError: String?

    let convoId: String
    private let currentUserId: String?
    private let service: SupabaseService
    private let storage: StorageService

    init(
        convoId: String,
        currentUserId: String?,
        service: SupabaseService = SupabaseService(),
        storage: StorageService = StorageService()
    ) {
        self.convoId = convoId
        self.currentUserId = currentUserId
        self.service = service
        self.storage = storage
    }

    func load() async {
        if messages.isEmpty { loadingState = .loading }
        do {
            let rows = try await service.getConvoMessages(convoId: convoId, limit: 50, offset: 0)
            messages = (await mapAll(rows)).sorted { $0.createdAt < $1.createdAt }
            loadingState = .loaded
            try? await service.markConvoRead(convoId: convoId)
        } catch {
            print("[ConversationVM] load: \(error)")
            if messages.isEmpty { loadingState = .error(error.localizedDescription) }
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        isSending = true

        let tempId = "local-\(UUID().uuidString)"
        let sentAt = Date()
        messages.append(ChatMessage(id: tempId, text: text, isFromMe: true, createdAt: sentAt,
                                    type: "message", isAttachment: false, attachmentURL: nil,
                                    attachmentType: nil, attachmentName: nil, pending: true))

        do {
            let newId = try await service.sendMessage(convoId: convoId, content: text)
            if let i = messages.firstIndex(where: { $0.id == tempId }) {
                messages[i] = ChatMessage(id: newId, text: text, isFromMe: true, createdAt: sentAt,
                                          type: "message", isAttachment: false, attachmentURL: nil,
                                          attachmentType: nil, attachmentName: nil, pending: false)
            }
        } catch {
            print("[ConversationVM] send: \(error)")
            messages.removeAll { $0.id == tempId }
            draft = text   // restore the unsent text so it isn't lost
        }
        isSending = false
    }

    /// Uploads + sends an attachment (with an optional caption from the draft).
    func sendAttachment(data: Data, fileName: String, fileType: String, caption: String) async {
        guard let userId = currentUserId, !isSending else { return }
        guard data.count <= 25 * 1024 * 1024 else {
            attachmentError = "File is too large (max 25 MB)."
            return
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let blocked: Set<String> = ["svg", "html", "htm", "xml", "php", "exe", "bat", "sh", "cmd"]
        guard !blocked.contains(ext) else {
            attachmentError = "That file type isn't allowed."
            return
        }

        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        let tempId = "local-\(UUID().uuidString)"
        let sentAt = Date()
        messages.append(ChatMessage(id: tempId, text: text, isFromMe: true, createdAt: sentAt,
                                    type: "message", isAttachment: true, attachmentURL: nil,
                                    attachmentType: fileType, attachmentName: fileName, pending: true))

        do {
            let path = try await service.uploadMessageAttachment(
                convoId: convoId, userId: userId, fileName: fileName, data: data, fileType: fileType
            )
            let newId = try await service.sendMessageWithAttachment(
                convoId: convoId, content: text, fileUrl: path, fileType: fileType,
                fileName: fileName, fileSize: data.count
            )
            let signed = (await storage.signAttachmentUrls(paths: [path])).first ?? nil
            if let i = messages.firstIndex(where: { $0.id == tempId }) {
                messages[i] = ChatMessage(id: newId, text: text, isFromMe: true, createdAt: sentAt,
                                          type: "message", isAttachment: true,
                                          attachmentURL: signed.flatMap { URL(string: $0) },
                                          attachmentType: fileType, attachmentName: fileName, pending: false)
            }
        } catch {
            print("[ConversationVM] sendAttachment: \(error)")
            messages.removeAll { $0.id == tempId }
            attachmentError = "Couldn't send the attachment."
        }
        isSending = false
    }

    /// Polls for new messages every few seconds while the thread is on screen.
    func startPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { break }
            await mergeLatest()
        }
    }

    private func mergeLatest() async {
        guard let rows = try? await service.getConvoMessages(convoId: convoId, limit: 50, offset: 0) else { return }
        let mapped = await mapAll(rows)
        let existing = Set(messages.map(\.id))
        let fresh = mapped.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }

        messages.append(contentsOf: fresh)
        messages.sort { $0.createdAt < $1.createdAt }
        if fresh.contains(where: { !$0.isFromMe }) {
            try? await service.markConvoRead(convoId: convoId)
        }
    }

    /// Maps rows to chat messages, batch-signing any attachment paths (private bucket).
    private func mapAll(_ rows: [ApiConvoMessage]) async -> [ChatMessage] {
        let paths: [String?] = rows.map { ($0.attachment ?? false) ? $0.attachmentUrl : nil }
        let signed = await storage.signAttachmentUrls(paths: paths)
        return rows.enumerated().map { idx, m in map(m, signedURL: signed[idx]) }
    }

    private func map(_ m: ApiConvoMessage, signedURL: String?) -> ChatMessage {
        let type = m.messageType ?? "message"
        let isAttachment = m.attachment ?? false
        return ChatMessage(
            id: m.messageId,
            text: m.content ?? "",
            isFromMe: type != "system" && m.userId != nil && m.userId == currentUserId,
            createdAt: MessageTime.parse(m.createdAt) ?? Date(),
            type: type,
            isAttachment: isAttachment,
            attachmentURL: signedURL.flatMap { URL(string: $0) },
            attachmentType: m.attachmentType,
            attachmentName: m.attachmentName
        )
    }
}
