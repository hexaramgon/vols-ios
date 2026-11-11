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
    /// The panel is on screen (swiped to / Comments tapped) — load right away.
    /// Off screen it waits for the track to settle first (see `.task` below).
    var isActive: Bool = false

    @Environment(PlayerController.self) var controller
    private let topAnchor = "comments-top"
    /// Comment whose options sheet (report / delete) is showing — opened by a
    /// long-press on the row, or the own-comment "…".
    @State private var optionsComment: ApiTrackComment?
    /// The list's bottom edge on screen (changes only with layout).
    @State private var listMaxY: CGFloat = .greatestFiniteMagnitude
    /// The list's UIScrollView — the reply glide measures its real visible
    /// area (it stretches into the keyboard's area while typing).
    @State private var listScroll = EnclosingScrollView.Box()
    /// Screen bottom of the comment being replied to (nil otherwise).
    @State private var replyRowMaxY: CGFloat?
    /// The end-of-list room while typing, and — for a beat after typing ends —
    /// held so the list can glide to its new end instead of snapping there.
    @State private var typingRoom: CGFloat = 0
    /// False from the moment typing starts until the list has glided to its
    /// post-keyboard end — the typing room stays in the content till then.
    @State private var roomReleased = true
    /// The list's bottom edge while nobody is typing — once the keyboard is up
    /// the scroll view stretches down into the keyboard's area.
    @State private var restListMaxY: CGFloat = .greatestFiniteMagnitude
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
        // The panel lives in the pager, mounted whenever the player is
        // expanded. Off screen, comments load only once the track has settled
        // for a moment — flicking through tracks (feed swipe, skips) fires no
        // request per skipped track. Opening the panel loads immediately; the
        // model dedups a key it already has. The offline "No connection"
        // indicator rides this load, so it still shows (a beat later).
        .task(id: CommentsLoadTrigger(key: currentFileId ?? currentTrackId, active: isActive)) {
            if !isActive {
                guard (try? await Task.sleep(for: .milliseconds(800))) != nil else { return }
            }
            await model.loadComments(trackId: currentTrackId, fileId: currentFileId)
        }
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
                onReply: { model.reply(to: comment) },
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
                subject: comment.user.username.map { "@\($0)" } ?? "Comment",
                alwaysDark: true
            )
        }
    }

    /// The heading with the count folded in — "Comments" while loading or
    /// empty, "1 Comment", "3 Comments" (comments + replies; the list loads
    /// in one page, so there's never a "+").
    private var commentsTitle: String {
        let n = model.comments.reduce(0) { $0 + 1 + ($1.replies?.count ?? 0) }
        if model.isLoading || n == 0 { return "Comments" }
        return n == 1 ? "1 Comment" : "\(n) Comments"
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(commentsTitle)
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                if model.isLoading {
                    ProgressView().tint(.white.opacity(0.4)).scaleEffect(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
    }

    // MARK: List

    /// How much of the list the lifted composer covers (0 when it's down).
    private var composerOverlap: CGFloat {
        guard model.composerTopY < listMaxY else { return 0 }
        return listMaxY - model.composerTopY + 8
    }

    /// Glides the replied-to comment so its bottom sits 8pt above the lifted
    /// composer — by exactly the measured distance, on the UIScrollView (which
    /// stretches into the keyboard's area while typing, so SwiftUI anchors on
    /// the list's frame landed it behind the composer).
    private func landReplyAboveComposer() {
        guard let sv = listScroll.scrollView, let rowMaxY = replyRowMaxY,
              model.composerTopY < .greatestFiniteMagnitude else { return }
        let delta = rowMaxY - (model.composerTopY - 8)
        let insets = sv.adjustedContentInset
        let maxY = max(-insets.top, sv.contentSize.height + insets.bottom - sv.bounds.height)
        let target = min(maxY, max(-insets.top, sv.contentOffset.y + delta))
        guard abs(target - sv.contentOffset.y) > 1 else { return }
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: target), animated: true)
    }

    private func settleAfterTyping() {
        if let sv = listScroll.scrollView, restListMaxY < .greatestFiniteMagnitude {
            let restHeight = restListMaxY - sv.convert(sv.bounds, to: nil).minY
            let endOffset = max(0, sv.contentSize.height - typingRoom - restHeight)
            if sv.contentOffset.y > endOffset + 1 {
                sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: endOffset), animated: true)
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if !model.composerFocused { roomReleased = true }
        }
    }

    /// Room at the end of the list. While the composer is focused it's at
    /// least how far the list stretches when the keyboard comes up: reserved
    /// from the moment focus lands (before the keyboard), the content is
    /// already tall enough when the list grows, so UIKit never has to pull
    /// the scroll offset back (that snap flung the top comments down on Reply).
    ///
    /// Once the composer has lifted, the scroll view reaches the screen's
    /// bottom (it stretches into the keyboard's area), so the room runs from
    /// there up to the composer's top — enough for the last comment to scroll
    /// clear above it.
    private var bottomRoom: CGFloat {
        if !model.composerFocused, !roomReleased { return typingRoom }
        guard model.composerFocused, restListMaxY < .greatestFiniteMagnitude else { return composerOverlap }
        let reserve = UIScreen.size.height - restListMaxY + 8
        guard model.composerTopY < .greatestFiniteMagnitude else { return max(composerOverlap, reserve) }
        let lifted = UIScreen.size.height - ViewConst.safeAreaInsets.bottom - model.composerTopY + 8
        return max(composerOverlap, reserve, lifted)
    }

    private var commentsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                // Eager, not lazy: `get_track_comments` returns a page of 20,
                // so every row is built up front. A LazyVStack built rows on
                // demand — the list stretching under the rising keyboard made
                // rows below the fold "visible" mid-animation, and a row built
                // then slid in from the top of the list (seen on Reply).
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 1).id(topAnchor)

                    if model.comments.isEmpty && !model.isLoading {
                        Text("No comments yet — be the first.")
                            .font(.appSubheadline)
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }

                    ForEach(model.comments) { comment in
                        let isReplyTarget = model.replyingTo?.id == comment.id
                        commentRow(comment)
                            .id(comment.id)
                            // The reply glide lands this row's bottom edge.
                            .onGeometryChange(for: CGFloat?.self) {
                                isReplyTarget ? $0.frame(in: .global).maxY : nil
                            } action: { y in
                                if let y { replyRowMaxY = y } else if isReplyTarget { replyRowMaxY = nil }
                            }
                        if let replies = comment.replies, !replies.isEmpty {
                            ForEach(replies) { reply in
                                commentRow(reply, isReply: true).padding(.leading, 36)
                            }
                        }
                    }
                }
                .background(EnclosingScrollView(box: listScroll))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // Extra room so the last comment can scroll clear of the fade.
                .padding(.bottom, 32)
                // Rows never animate their layout: the keyboard / composer lift
                // and the reply scroll run animated, and a lazily-built row
                // created mid-animation flew in from nowhere. The scroll itself
                // still animates (it's the scroll view's offset, not the rows),
                // and the rows' own `.animation(_:value:)` washes still run.
                .transaction { $0.animation = nil }

                // While typing, the lifted composer + keyboard cover the list's
                // bottom: this much room at the END OF THE CONTENT lets the last
                // comments scroll clear of it. Content, not a safe-area inset —
                // an inset (or the keyboard's own safe area) changing as the
                // keyboard hid made UIKit re-adjust the scroll offset, which
                // threw the list ~280pt on tap-out. A shrinking content size
                // leaves the offset alone.
                Color.clear.frame(height: bottomRoom)
                    .onChange(of: bottomRoom, initial: true) { _, room in
                        if model.composerFocused { typingRoom = room }
                    }
                }
            }
            // The list doesn't take the keyboard as an inset (that inset
            // vanishing on dismiss is what made UIKit re-adjust the offset).
            .ignoresSafeArea(.keyboard)
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(scrollLocked)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                listMaxY = $0.maxY
                if !model.composerFocused, model.composerTopY == .greatestFiniteMagnitude {
                    restListMaxY = $0.maxY
                }
            }
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
            // Tap anywhere in the list to dismiss the keyboard (collapses the input)
            // — except a tap on Reply, which keeps typing (it fired alongside the
            // button and dropped the keyboard only for Reply to raise it again).
            // Checked a beat later, as the button's action may run after this.
            .simultaneousGesture(TapGesture().onEnded {
                let request = model.replyRequest
                DispatchQueue.main.async {
                    guard model.replyRequest == request else { return }
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            })
            // New comments land at the top (RPC returns newest-first) — reveal them.
            .onChange(of: model.comments.first?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(topAnchor, anchor: .top) }
            }
            // Typing ended: the list is about to lose its keyboard room. Glide
            // to where its end will be, THEN drop the room — otherwise UIKit
            // snaps the offset there in one frame.
            .onChange(of: model.composerFocused) { wasFocused, focused in
                if focused { roomReleased = false; return }
                if wasFocused { settleAfterTyping() }
            }
            // Replying (Instagram-style, like the listing page): once the
            // composer is up, glide the comment to sit just above it.
            .onChange(of: model.replyRequest) { _, _ in
                guard model.replyingTo != nil else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    landReplyAboveComposer()
                }
            }
            // Opened from the live comment toast: bring that comment into view,
            // highlighted, then let the highlight fade after a moment.
            .onChange(of: model.highlightedCommentId, initial: true) { _, id in
                guard let id else { return }
                withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if model.highlightedCommentId == id {
                        withAnimation(.easeOut(duration: 0.6)) { model.highlightedCommentId = nil }
                    }
                }
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
                ExpandableText(comment.content, textColor: .vText)

                actionsRow(comment, isReply: isReply)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        // Highlight the held comment while its options sheet is up (the sheet dims
        // the whole panel, so this lifts the one being acted on), and the one
        // opened from the live comment toast.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(optionsComment?.id == comment.id ? 0.09
                                     : (model.highlightedCommentId == comment.id
                                        || model.replyingTo?.id == comment.id) ? 0.12 : 0))
                // Only the wash animates — on the whole row this animation
                // also caught the reply's relayout and flew other rows around.
                .animation(.easeOut(duration: 0.2), value: model.replyingTo?.id)
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

    /// Just Reply (top-level comments). Copy / Delete (your own) / Report
    /// live behind the long-press options sheet.
    @ViewBuilder
    private func actionsRow(_ comment: ApiTrackComment, isReply: Bool) -> some View {
        if !isReply {
            actionButton(.reply, "Reply") { model.reply(to: comment) }
        }
    }

    private func actionButton(_ icon: LucideIcon.Name, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                LucideIcon(icon, .sm)
                Text(title).font(.appCaption.weight(.semibold))
            }
            .foregroundStyle(Color.vText2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
    /// Runs once the Delete confirm (the centered modal) is accepted.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingConfirm: DestructiveConfirm?

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
                        pendingConfirm = DestructiveConfirm(
                            title: "Delete this comment?",
                            message: "This can't be undone."
                        ) { onDelete() }
                    }
                } else {
                    OptionSheetRow(icon: .triangleAlert, title: "Report") {
                        dismiss()
                        onReport()
                    }
                }
            }
            .padding(.top, 6)
            .confirmModal($pendingConfirm)
        }
        .selfSizedDetent()
        .sheetBackground(alwaysDark: true)
    }
}

/// What the comments load is keyed on: the track / file, and whether the
/// panel is on screen (flipping to on screen skips the settle delay).
private struct CommentsLoadTrigger: Equatable {
    let key: String?
    let active: Bool
}
