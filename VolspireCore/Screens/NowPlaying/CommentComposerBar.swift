//
//  CommentComposerBar.swift
//  Volspire
//
//  The comment input at the bottom of the player: a rounded card with the text
//  field and a timestamp row (pin the current playback position to the comment),
//  on an opaque bar so the comments can't bleed through when it lifts over them.
//

import DesignSystem
import Kingfisher
import Player
import Services
import SwiftUI
import UIKit

struct CommentComposerBar: View {
    @Bindable var model: NowPlayingCommentsModel
    var composerNamespace: Namespace.ID?

    @Environment(PlayerController.self) private var controller
    @FocusState private var isFocused: Bool

    @State private var keyboardTopY: CGFloat = .greatestFiniteMagnitude
    @State private var barMaxY: CGFloat = 0

    private var currentFileId: String? { controller.currentFileId }
    private var currentTrackId: String? {
        currentFileId == nil ? controller.state.currentMediaID?.value : nil
    }

    private var keyboardOverlap: CGFloat {
        guard keyboardTopY < barMaxY else { return 0 }
        return barMaxY - keyboardTopY + 8
    }

    private var keyboardVisible: Bool { keyboardTopY < .greatestFiniteMagnitude }

    /// Expands into the full card (timestamp row + send) only while focused;
    /// dismissing the keyboard collapses it back to the slim one-line pill.
    private var expanded: Bool { isFocused }

    /// Bottom inset for the card: clears the home indicator when the keyboard is
    /// down, sits tight to the keyboard when it's up.
    private var bottomInset: CGFloat {
        keyboardVisible ? 8 : max(ViewConst.safeAreaInsets.bottom, 14)
    }

    // MARK: Timestamp state

    /// True once the playhead has passed the dropped start, so a range can end.
    private var canStop: Bool {
        guard let start = model.commentTimestamp, model.commentTimestampEnd == nil else { return false }
        return (controller.progress?.elapsedTime ?? 0).rounded(.down) > start
    }

    private var placeholder: String {
        if let username = model.replyingTo?.user.username { return "Reply to @\(username)…" }
        return "Add a comment…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = model.sendError {
                Text(err)
                    .font(.appCaption)
                    .foregroundStyle(Color.vError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            if expanded, let replyingTo = model.replyingTo {
                replyBanner(replyingTo)
            }

            HStack(alignment: .center, spacing: 10) {
                avatar(model.currentUser?.profileImageUrl, name: model.currentUser?.username, size: 28)

                TextField(placeholder, text: $model.commentText, axis: .vertical)
                    .font(.appBody)
                    // Grow up to 6 lines while typing; collapse to a single
                    // truncated line once dismissed so the pill preview stays slim.
                    .lineLimit(expanded ? 1 ... 6 : 1 ... 1)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isFocused)
                    .submitLabel(.send)

                // Collapsed pill with text: keep a send button so you can post
                // without re-opening the keyboard (expanded puts send in the row below).
                if !expanded && (model.canSend || model.isSending) {
                    sendButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Timestamp + send row only once expanded (typing).
            if expanded {
                Divider()
                    .overlay(Color.white.opacity(0.1))
                    .padding(.horizontal, 14)

                HStack(spacing: 8) {
                    if model.commentTimestamp == nil {
                        // Clock: drop the start at the current position.
                        Button { dropTimestamp() } label: {
                            LucideIcon(.clock, .xl)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Start dropped → show it, plus Stop (make range) and Clear.
                        timestampChip
                        if canStop {
                            chipButton(systemImage: "stop.fill", label: "Stop") { stopRange() }
                        }
                        chipButton(systemImage: "xmark", label: "Clear") { clearTimestamp() }
                    }

                    Spacer(minLength: 0)
                    if model.canSend || model.isSending {
                        sendButton
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .transition(.opacity)
                .animation(.smooth(duration: 0.2), value: canStop)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: expanded ? 22 : 24, style: .continuous)
                .fill(Color.white.opacity(expanded ? 0.07 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: expanded ? 22 : 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(expanded ? 0.08 : 0))
                )
        )
        .matchedComposer(composerNamespace)
        // Wider than the rest of the player content so the input reads as its own bar.
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
        // Opaque bar only when expanded (lifted over the comments); the collapsed
        // pill sits below the comments and needs no backing.
        .background(alignment: .top) {
            if expanded { barBackground }
        }
        .offset(y: -keyboardOverlap)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { barMaxY = geo.frame(in: .global).maxY }
                    .onChange(of: geo.frame(in: .global).maxY) { _, value in barMaxY = value }
            }
        )
        .animation(.smooth(duration: 0.28), value: expanded)
        .animation(.easeOut(duration: 0.25), value: keyboardTopY)
        // Send button scale-fades in when there's something to post (matches chat).
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.canSend)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notif in
            if let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardTopY = frame.minY
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardTopY = .greatestFiniteMagnitude
        }
        // Tapping "Reply" on a comment focuses the input.
        .onChange(of: model.replyingTo?.commentId) { _, newValue in
            if newValue != nil { isFocused = true }
        }
        // Return posts the comment instead of inserting a newline paragraph. A
        // vertical-axis TextField turns the keyboard return into a "\n"; catch that
        // trailing newline, strip it, and send. (`.onSubmit` never fires for a
        // multi-line field, so this is the reliable way.)
        .onChange(of: model.commentText) { _, newValue in
            guard newValue.hasSuffix("\n") else { return }
            model.commentText = String(newValue.dropLast())
            model.send(trackId: currentTrackId, fileId: currentFileId)
        }
        // Share focus with the comments panel so a tap there dismisses the keyboard
        // instead of opening a profile. (`@FocusState` updates after the tap, so it
        // stays true through the dismissing tap — no race like keyboard notifications.)
        .onChange(of: isFocused) { _, focused in
            model.composerFocused = focused
        }
    }

    /// "Replying to @user" banner with a cancel button.
    private func replyBanner(_ comment: ApiTrackComment) -> some View {
        HStack(spacing: 6) {
            Text("Replying to @\(comment.user.username ?? "user")")
                .font(.appCaption)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
            Button { model.replyingTo = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    // MARK: Pieces

    /// Drops the start at the current position (whole seconds — the column is an
    /// integer, matching the web's Math.floor).
    private func dropTimestamp() {
        let now = (controller.progress?.elapsedTime ?? 0).rounded(.down)
        withAnimation(.smooth(duration: 0.2)) { model.commentTimestamp = now }
    }

    /// Ends the range at the current position (only once the playhead is past start).
    private func stopRange() {
        let now = (controller.progress?.elapsedTime ?? 0).rounded(.down)
        guard let start = model.commentTimestamp, now > start else { return }
        withAnimation(.smooth(duration: 0.2)) { model.commentTimestampEnd = now }
    }

    private func clearTimestamp() {
        withAnimation(.smooth(duration: 0.2)) {
            model.commentTimestamp = nil
            model.commentTimestampEnd = nil
        }
    }

    /// Read-only chip showing the dropped start (or start → end range).
    private var timestampChip: some View {
        HStack(spacing: 4) {
            LucideIcon(.clock, .xs).foregroundStyle(.white.opacity(0.55))
            Text((model.commentTimestamp ?? 0).asTimeString(style: .positional)).monospacedDigit()
            if let end = model.commentTimestampEnd {
                Text("→").foregroundStyle(.white.opacity(0.45))
                Text(end.asTimeString(style: .positional)).monospacedDigit()
            }
        }
        .font(.appCaptionMedium)
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    /// A small labelled pill button (Stop / Clear) beside the timestamp chip.
    private func chipButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
            }
            .font(.appCaptionMedium)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Up-arrow in an accent-gradient circle — the same send button as the chat
    /// input, scale-fading in when there's something to post.
    @ViewBuilder
    private var sendButton: some View {
        Group {
            if model.isSending {
                ProgressView()
                    .tint(.white)
                    .frame(width: 32, height: 32)
            } else {
                Button { model.send(trackId: currentTrackId, fileId: currentFileId) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(LinearGradient.sendAccent, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 2)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private func avatar(_ urlString: String?, name: String?, size: CGFloat) -> some View {
        AvatarView(urlString: urlString, name: name, size: size)
    }

    /// Frosted, darkened bar that extends far down so the gap to the keyboard stays
    /// covered after the lift offset.
    private var barBackground: some View {
        Rectangle()
            .fill(.regularMaterial)
            .frame(height: 800)
            .overlay(Color.black.opacity(0.2))
            .allowsHitTesting(false)
    }
}

extension View {
    /// Comments-button ⇄ input-card morph (shared id "commentComposer"). Applied
    /// only when a namespace is provided (skipped in previews).
    @ViewBuilder
    func matchedComposer(_ namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: "commentComposer", in: namespace)
        } else {
            self
        }
    }
}
