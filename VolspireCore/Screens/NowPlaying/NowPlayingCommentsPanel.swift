//
//  NowPlayingCommentsPanel.swift
//  Volspire
//

import DesignSystem
import Kingfisher
import Player
import Services
import SwiftUI

struct NowPlayingCommentsPanel: View {
    @Environment(PlayerController.self) var controller
    @State private var commentText: String = ""
    @State private var comments: [ApiTrackComment] = []
    @State private var isLoading: Bool = false
    @State private var isSending: Bool = false
    @State private var loadedTrackId: String?
    @FocusState private var isInputFocused: Bool

    private let supabaseService = SupabaseService()

    private var currentTrackId: String? {
        controller.state.currentMediaID?.value
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Comments")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                Spacer()
                if isLoading {
                    ProgressView()
                        .tint(.white.opacity(0.4))
                        .scaleEffect(0.7)
                } else {
                    Text("\(comments.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Comments list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if comments.isEmpty && !isLoading {
                        Text("No comments yet")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }

                    ForEach(comments) { comment in
                        commentRow(comment: comment)

                        // Replies
                        if let replies = comment.replies, !replies.isEmpty {
                            ForEach(replies) { reply in
                                commentRow(comment: reply)
                                    .padding(.leading, 32)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)

            Divider()
                .overlay(Color.white.opacity(0.15))

            // Input bar
            HStack(spacing: 10) {
                TextField("Add a comment…", text: $commentText)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .disabled(isSending)
                    .onSubmit {
                        sendComment()
                    }

                if isInputFocused {
                    if isSending {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .scaleEffect(0.7)
                            .transition(.opacity.combined(with: .scale))
                    } else if !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            sendComment()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .transition(.opacity.combined(with: .scale))
                    }

                    Button {
                        commentText = ""
                        isInputFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .animation(.easeInOut(duration: 0.2), value: isInputFocused)
        }
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .task(id: currentTrackId) {
            await loadComments()
        }
    }

    private func sendComment() {
        let content = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let trackId = currentTrackId else { return }
        commentText = ""
        isSending = true

        Task {
            defer { isSending = false }
            do {
                try await supabaseService.postComment(content: content, trackId: trackId)
                // Refresh comments list
                loadedTrackId = nil
                await loadComments()
                isInputFocused = false
            } catch {
                print("[NowPlayingCommentsPanel] Failed to post comment: \(error)")
                // Restore text so user can retry
                commentText = content
            }
        }
    }

    private func loadComments() async {
        guard let trackId = currentTrackId, trackId != loadedTrackId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            comments = try await supabaseService.getTrackComments(trackId: trackId)
            loadedTrackId = trackId
        } catch {
            print("[NowPlayingCommentsPanel] Failed to load comments: \(error)")
            comments = []
        }
    }

    private func commentRow(comment: ApiTrackComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageUrl = comment.user.profileImageUrl, let url = URL(string: imageUrl) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text((comment.user.username ?? "?").prefix(1).uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.user.username ?? "Unknown")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(relativeTime(from: comment.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Text(comment.content)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
    }

    /// Parses an ISO-8601 date string and returns a relative time label.
    private func relativeTime(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else { return "" }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController.stub
    ZStack {
        Color.black.ignoresSafeArea()
        NowPlayingCommentsPanel()
            .frame(height: 400)
            .padding(.horizontal, 25)
    }
    .environment(playerController)
}
