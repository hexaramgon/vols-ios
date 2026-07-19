//
//  ReportSheet.swift
//  Volspire
//
//  Reusable "Report" bottom sheet for App Store 1.2 UGC safety — pick a reason,
//  optionally add details, submit. Files the report via `submitReport`; the
//  backend auto-hides the target on severe categories or a report threshold.
//  Shown on OTHER people's content only (tracks, comments, DMs, listings,
//  profiles, packs). Sizes to its content like the other option sheets.
//

import DesignSystem
import Services
import SwiftUI

struct ReportSheet: View {
    let targetType: ReportTargetType
    let targetId: String
    /// What's being reported — shown in the header subtitle (e.g. "@nvs", a title).
    let subject: String

    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var selected: ReportReason?
    @State private var details = ""
    @State private var submitting = false
    @State private var submitted = false
    @State private var errorText: String?
    @FocusState private var detailsFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SheetHeader(
                    icon: .flag,
                    title: submitted ? "Report received" : "Report",
                    subtitle: subject
                ) { dismiss() }

                if submitted {
                    confirmation
                } else {
                    form
                }
            }
            // Sized to its content — shrinks to the confirmation state after
            // submitting.
            .selfSizedDetent()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity)
        .sheetBackground()
    }

    // MARK: Confirmation

    private var confirmation: some View {
        VStack(spacing: 14) {
            LucideIcon(.circleCheck, .hero).foregroundStyle(Color.green)
            Text("Thanks for letting us know")
                .font(.appHeadline).foregroundStyle(.white)
            Text("We review every report and act on violations within 24 hours.")
                .font(.appSubheadline).foregroundStyle(Color.vText2)
                .multilineTextAlignment(.center)

            PrimaryButton("Done") { dismiss() }
                .padding(.top, 10)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Why are you reporting this?")
                .font(.appFootnote).foregroundStyle(Color.vText3)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)

            ForEach(ReportReason.allCases, id: \.self, content: reasonRow)

            VStack(alignment: .leading, spacing: 8) {
                Text("Add details (optional)")
                    .font(.appFootnote).foregroundStyle(Color.vText3)
                TextField(
                    "",
                    text: $details,
                    prompt: Text("What happened?").foregroundStyle(Color.vText3),
                    axis: .vertical
                )
                .font(.appCallout).foregroundStyle(.white).tint(.white)
                .lineLimit(2 ... 4)
                .focused($detailsFocused)
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20).padding(.top, 18)

            if let errorText {
                ErrorBanner(errorText).padding(.horizontal, 20).padding(.top, 12)
            }

            submitButton.padding(20)
        }
    }

    private func reasonRow(_ reason: ReportReason) -> some View {
        Button {
            detailsFocused = false
            withAnimation(.snappy(duration: 0.15)) { selected = reason }
        } label: {
            HStack(spacing: 12) {
                Text(reason.label).font(.appBody).foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if selected == reason {
                    Circle().fill(Color.white)
                        .frame(width: 20, height: 20)
                } else {
                    Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var submitButton: some View {
        PrimaryButton("Submit report", busy: submitting, enabled: selected != nil, action: submit)
    }

    private func submit() {
        guard let selected else { return }
        submitting = true
        errorText = nil
        Task {
            do {
                try await dependencies.supabaseService.submitReport(
                    targetType: targetType,
                    targetId: targetId,
                    reason: selected,
                    // Matches the server-side `content_reports.details` CHECK length.
                    details: details.isEmpty ? nil : String(details.prefix(2000))
                )
                submitting = false
                // Stays up until the user taps Done (or the header close) —
                // no auto-dismiss.
                withAnimation(.snappy) { submitted = true }
            } catch {
                submitting = false
                errorText = "Couldn't submit your report. Please try again."
            }
        }
    }
}
