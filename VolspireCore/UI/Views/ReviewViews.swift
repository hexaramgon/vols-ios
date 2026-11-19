//
//  ReviewViews.swift
//  Volspire
//
//  Pack / service reviews (the web's `review-form` + `review-list`, on the
//  same `reviews` backend): `WriteReviewSheet` (1–5 stars + optional text →
//  `create_review`), `ReviewStars` (the read-only row of stars),
//  `ReviewRow` (one review; press and hold for its options) and
//  `ReviewOptionsSheet` (Copy, then Delete on yours / Report on others' —
//  the comment options pattern).
//

import DesignSystem
import Services
import SwiftUI

// MARK: - Stars

/// Five stars, filled up to `rating` (rounded to the nearest whole star).
struct ReviewStars: View {
    let rating: Double
    var size: IconSize = .xs

    var body: some View {
        let filled = Int(rating.rounded())
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { star in
                LucideIcon(star <= filled ? .starFill : .star, size)
                    .foregroundStyle(star <= filled ? Color.vRating : Color.vText4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(filled) out of 5 stars")
    }
}

// MARK: - Summary

/// The section's lead: big average, its stars, "N reviews".
struct ReviewSummary: View {
    let average: Double
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%.1f", average))
                .font(.appTitleXXL)
                .foregroundStyle(Color.vText)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 4) {
                ReviewStars(rating: average, size: .md)
                Text(count == 1 ? "1 review" : "\(count.compactCount) reviews")
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Row

/// One review, laid out like a listing comment: avatar, @name + when (+
/// Verified), the stars, then the text. Press and hold for its options
/// (`onLongPress`), like comments.
struct ReviewRow: View {
    let review: ApiReview
    var onProfile: ((String) -> Void)? = nil
    var onLongPress: (() -> Void)? = nil

    private var username: String { review.reviewer?.username ?? "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { openProfile() } label: {
                AvatarView(urlString: review.reviewer?.profileImageUrl, name: username, size: 32)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Button { openProfile() } label: {
                        Text("@\(username)")
                            .font(.appSubheadlineSemibold)
                            .foregroundStyle(Color.vText)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    if let created = review.createdAt {
                        Text(MessageTime.ago(MessageTime.parse(created)))
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                            .monospacedDigit()
                    }
                    if review.verified == true {
                        HStack(spacing: 3) {
                            LucideIcon(.shield, .xs)
                            Text("Verified").font(.appCaptionMedium)
                        }
                        .foregroundStyle(Color.vText2)
                        .accessibilityLabel("Verified purchase")
                    }
                }

                if let rating = review.rating {
                    ReviewStars(rating: rating, size: .sm)
                        .padding(.top, 4)
                }

                if let body = review.body, !body.isEmpty {
                    // Near-full ink, like listing comments.
                    ExpandableText(body, font: .appSubheadline, textColor: Color.vTextRow)
                        .padding(.top, 6)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onLongPressGesture(minimumDuration: 0.35) {
            guard let onLongPress else { return }
            Haptics.impact(.medium)
            onLongPress()
        }
        .accessibilityAction(named: "Review options") { onLongPress?() }
    }

    private func openProfile() {
        if let id = review.reviewer?.userId { onProfile?(id) }
    }
}

// MARK: - Options

/// Press-and-hold options for a review — the same `SheetHeader` + rows as the
/// comment options sheets: Copy, then Delete (yours, after the centered
/// confirm) or Report (someone else's).
struct ReviewOptionsSheet: View {
    let review: ApiReview
    let isMine: Bool
    /// Signed in — Report needs an account.
    let canReport: Bool
    let onReport: () -> Void
    /// Runs once the Delete confirm is accepted.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingConfirm: DestructiveConfirm?

    private var bodyText: String? {
        guard let body = review.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
        return body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: .star,
                title: review.reviewer?.username ?? "Review",
                subtitle: bodyText ?? review.rating.map { "\(Int($0.rounded())) out of 5 stars" }
            ) { dismiss() }

            VStack(spacing: 0) {
                if let bodyText {
                    OptionSheetRow(icon: .copy, title: "Copy") {
                        UIPasteboard.general.string = bodyText
                        dismiss()
                    }
                }
                if isMine {
                    OptionSheetRow(icon: .trash2, title: "Delete review", tint: .vError) {
                        pendingConfirm = DestructiveConfirm(
                            title: "Delete your review?",
                            message: "Your rating and review will be removed.",
                            actionLabel: "Delete review"
                        ) { onDelete() }
                    }
                } else if canReport {
                    OptionSheetRow(icon: .flag, title: "Report") {
                        dismiss()
                        onReport()
                    }
                }
            }
            .padding(.top, 6)
            .confirmModal($pendingConfirm)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}

// MARK: - Write

/// Pick 1–5 stars, optionally say why, post. Calls `onPosted` after a
/// successful `create_review` so the page can reload.
struct WriteReviewSheet: View {
    let targetId: String
    let target: SupabaseService.ReviewTarget
    /// The pack / service name — the header subtitle.
    let subject: String
    let onPosted: () -> Void

    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var rating = 0
    @State private var text = ""
    @State private var posting = false
    @State private var errorText: String?
    @FocusState private var textFocused: Bool

    private static let ratingWords = ["", "Poor", "Fair", "Good", "Great", "Excellent"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(icon: .star, title: "Write a review", subtitle: subject) { dismiss() }

                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        ForEach(1 ... 5, id: \.self) { star in
                            Button {
                                textFocused = false
                                rating = star
                            } label: {
                                LucideIcon(star <= rating ? .starFill : .star, .xxl)
                                    .foregroundStyle(star <= rating ? Color.vRating : Color.vText3)
                                    .frame(width: 44, height: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                            .accessibilityAddTraits(star == rating ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: rating)
                    .animation(.snappy(duration: 0.15), value: rating)

                    Text(rating == 0 ? "Tap a star to rate" : Self.ratingWords[rating])
                        .font(.appFootnote)
                        .foregroundStyle(rating == 0 ? Color.vText3 : Color.vText2)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 8) {
                    SheetFieldLabel("Your review", optional: true)
                    TextField(
                        "",
                        text: $text,
                        prompt: Text("What did you like? What could be better?").foregroundStyle(Color.vText3),
                        axis: .vertical
                    )
                    .font(.appBody).foregroundStyle(Color.vText).tint(Color.vText)
                    .lineLimit(3 ... 6)
                    .charLimited($text, InputLimits.review)
                    .focused($textFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(textFocused ? Color.vFieldFocus : Color.vField,
                                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                    Text("\(text.limitCount)/\(InputLimits.review)")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)

                if let errorText {
                    ErrorBanner(errorText).padding(.horizontal, 20).padding(.top, 12)
                }

                CancelSendButtons(
                    sendTitle: "Post Review",
                    canSend: rating > 0,
                    isSending: posting,
                    onCancel: { dismiss() },
                    onSend: post
                )
                .padding(20)
            }
            .selfSizedDetent()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity)
        .sheetBackground()
    }

    private func post() {
        guard rating > 0, !posting else { return }
        posting = true
        errorText = nil
        Task {
            do {
                try await dependencies.supabaseService.createReview(
                    targetId: targetId,
                    target: target,
                    rating: rating,
                    body: text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                posting = false
                onPosted()
                dismiss()
                ToastCenter.shared.show("Review posted")
            } catch {
                posting = false
                errorText = "Couldn't post your review. Please try again."
            }
        }
    }
}
