//
//  NowPlayingCommentsPanel.swift
//  Volspire
//

import DesignSystem
import Kingfisher
import Player
import Services
import SwiftUI
import UIKit

/// The comments list (header + scrollable list) that slides into the artwork box.
/// The input bar is a separate `CommentComposerBar` at the bottom of the player
/// (the Comments button morphs into it), sharing state via the model.
struct NowPlayingCommentsPanel: View {
    var model: NowPlayingCommentsModel
    /// Collapse back to the artwork (shown as a chevron in the header).
    var onClose: () -> Void = {}
    /// Reports whether the list is scrolled to the very top, so the player's
    /// dismiss gesture knows when a downward drag should dismiss (only from the
    /// top) vs. scroll the comments.
    var atTop: Binding<Bool> = .constant(true)
    /// Set while the player is being dragged down to dismiss — freezes the list so
    /// it doesn't rubber-band away from the rest of the player during the drag.
    var scrollLocked: Bool = false

    @Environment(PlayerController.self) var controller
    private let topAnchor = "comments-top"
    /// Comment whose options sheet (report / delete) is showing — opened by a
    /// long-press on the row, or the own-comment "…".
    @State private var optionsComment: ApiTrackComment?
    /// Staged when "Report" is tapped; presented once the options sheet has
    /// dismissed (avoids a sheet-over-sheet transition).
    @State private var pendingReportComment: ApiTrackComment?
    @State private var reportingComment: ApiTrackComment?

    /// Non-nil when a workspace file is playing — its comments load instead of track ones.
    private var currentFileId: String? { controller.currentFileId }
    private var currentTrackId: String? {
        currentFileId == nil ? controller.state.currentMediaID?.value : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            commentsList
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        // TODO: This panel is in the pager so its `.task` fires as soon as the
        // player expands — comments load eagerly for every track. Make this lazy:
        // only fetch when the user actually swipes to the comments panel.
        // NOTE: when made lazy, move the offline "No connection" indicator
        // (RegularNowPlaying, driven by `model.loadFailed`) onto a request that
        // runs on expand (e.g. track metadata), or it won't show until a swipe.
        .task(id: currentFileId ?? currentTrackId) { await model.loadComments(trackId: currentTrackId, fileId: currentFileId) }
        .task { await model.loadCurrentUser() }
        .sheet(item: $optionsComment, onDismiss: {
            if let comment = pendingReportComment {
                pendingReportComment = nil
                reportingComment = comment
            }
        }) { comment in
            CommentOptionsSheet(
                comment: comment,
                isOwn: model.isOwn(comment),
                onReply: { model.replyingTo = comment },
                onReport: { pendingReportComment = comment },
                onDelete: { model.delete(commentId: comment.commentId, trackId: currentTrackId, fileId: currentFileId) }
            )
        }
        .sheet(item: $reportingComment) { comment in
            // This panel shows track comments or workspace-file comments; report
            // each against its own target type so moderation matches.
            ReportSheet(
                targetType: currentFileId != nil ? .fileComment : .trackComment,
                targetId: comment.commentId,
                subject: comment.user.username.map { "@\($0)" } ?? "Comment"
            )
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Comments")
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(.white)
                if model.isLoading {
                    ProgressView().tint(.white.opacity(0.4)).scaleEffect(0.7)
                } else {
                    Text("\(model.comments.count)")
                        .font(.appFootnote)
                        .foregroundStyle(.white.opacity(0.45))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().overlay(Color.white.opacity(0.1))
        }
    }

    // MARK: List

    private var commentsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 1).id(topAnchor)

                    if model.comments.isEmpty && !model.isLoading {
                        Text("No comments yet — be the first.")
                            .font(.appSubheadline)
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }

                    ForEach(model.comments) { comment in
                        commentRow(comment)
                        if let replies = comment.replies, !replies.isEmpty {
                            ForEach(replies) { reply in
                                commentRow(reply, isReply: true).padding(.leading, 36)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // Extra room so the last comment can scroll clear of the fade.
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(scrollLocked)
            // Soft bottom edge: comments dissolve out over the last ~32pt
            // instead of hard-clipping at the card's bottom.
            .mask(
                VStack(spacing: 0) {
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 32)
                }
            )
            // Track whether we're pinned to the top so the player only treats a
            // downward drag as a dismiss when there's nothing above to scroll to.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, isTop in
                if atTop.wrappedValue != isTop { atTop.wrappedValue = isTop }
            }
            // Tap anywhere in the list to dismiss the keyboard (collapses the input).
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
            // New comments land at the top (RPC returns newest-first) — reveal them.
            .onChange(of: model.comments.first?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(topAnchor, anchor: .top) }
            }
        }
    }

    // MARK: Rows

    private func commentRow(_ comment: ApiTrackComment, isReply: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { openProfile(comment.user.userId) } label: {
                avatar(comment.user.profileImageUrl, name: comment.user.username, size: 30)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button { openProfile(comment.user.userId) } label: {
                        Text(comment.user.username ?? "Unknown")
                            .font(.appLabel)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    if let ts = comment.timestampSeconds {
                        Button { controller.seek(to: ts) } label: {
                            Text(ts.asTimeString(style: .positional))
                                .font(.appMicroSemibold)
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Text(relativeTime(from: comment.createdAt))
                        .font(.appCaption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
                ExpandableText(comment.content)

                if !isReply {
                    Button("Reply") { model.replyingTo = comment }
                        .font(.appFootnoteMedium)
                        .foregroundStyle(.white.opacity(0.45))
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        // Highlight the held comment while its options sheet is up (the sheet dims
        // the whole panel, so this lifts the one being acted on).
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(optionsComment?.id == comment.id ? 0.09 : 0))
                .padding(.horizontal, -10)
                .padding(.vertical, -8)
        )
        .animation(.easeOut(duration: 0.05), value: optionsComment?.id)
        // Long-press any comment to open its options (report / delete your own).
        .onLongPressGesture(minimumDuration: 0.35) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            optionsComment = comment
        }
    }

    @ViewBuilder
    private func avatar(_ urlString: String?, name: String?, size: CGFloat) -> some View {
        AvatarView(urlString: urlString, name: name, size: size)
    }

    /// Navigates to a commenter's profile. Setting `pendingProfileNavigation`
    /// collapses the player and pushes the profile onto the active tab (handled
    /// in `OverlaidRootView`).
    private func openProfile(_ userId: String) {
        // While the composer is focused, a tap dismisses the keyboard instead of
        // navigating — so it takes a second, deliberate tap to open a profile.
        guard !model.composerFocused else {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            return
        }
        guard !userId.isEmpty else { return }
        controller.pendingProfileNavigation = userId
    }

    /// Parses an ISO-8601 date string and returns a relative time label
    /// in the app-wide compact vocabulary ("5m" / "2h").
    private func relativeTime(from dateString: String) -> String {
        MessageTime.ago(MessageTime.parse(dateString))
    }
}

// MARK: - Comment options sheet

/// Long-press / "…" options for a comment: Report (any comment) + Delete (own).
private struct CommentOptionsSheet: View {
    let comment: ApiTrackComment
    let isOwn: Bool
    let onReply: () -> Void
    let onReport: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Only top-level comments can be replied to (one-level threading).
    private var canReply: Bool { comment.parentId == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: .messageCircle,
                title: comment.user.username ?? "Comment",
                subtitle: comment.content
            ) { dismiss() }

            VStack(spacing: 0) {
                if canReply {
                    OptionSheetRow(icon: .reply, title: "Reply") {
                        dismiss()
                        onReply()
                    }
                }
                OptionSheetRow(icon: .copy, title: "Copy") {
                    UIPasteboard.general.string = comment.content
                    dismiss()
                }
                if isOwn {
                    OptionSheetRow(icon: .trash2, title: "Delete comment", tint: .vError) {
                        dismiss()
                        onDelete()
                    }
                } else {
                    OptionSheetRow(icon: .triangleAlert, title: "Report") {
                        dismiss()
                        onReport()
                    }
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}
