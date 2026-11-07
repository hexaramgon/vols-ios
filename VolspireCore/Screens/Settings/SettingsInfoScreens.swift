//
//  SettingsInfoScreens.swift
//  Volspire
//
//  Native Help Center + legal documents (Terms, Privacy) — the same copy as
//  volspire.com/support, /terms and /privacy, rendered in-app so Settings has
//  no external web links. Update the copy here whenever the web pages change.
//

import DesignSystem
import SwiftUI

// MARK: - Document model

/// A legal/info document: header metadata + titled sections (optionally with
/// sub-headed blocks) — mirrors the web terms/privacy page structure.
struct SettingsDoc {
    struct Subsection {
        let heading: String
        let text: String
    }

    struct Section {
        let title: String
        var body: String? = nil
        var subsections: [Subsection] = []
    }

    let eyebrow: String
    let title: String
    let updated: String
    let sections: [Section]
}

// MARK: - Document screen

/// Renders a `SettingsDoc` in the app theme: eyebrow, big Geist title,
/// last-updated line, then the sections.
struct SettingsDocScreen: View {
    let doc: SettingsDoc
    /// True when presented modally (the signup Terms/Privacy links): sheet
    /// chrome — drag indicator + a floating X — instead of the pushed-screen
    /// nav bar, which pads for the window's status-bar inset and renders a
    /// dead band + stray back chevron inside a sheet.
    var inSheet = false

    @Environment(\.dismiss) private var dismiss
    // Optional: also presented from the pre-login signup flow, which has no
    // PlayerController in the environment.
    @Environment(PlayerController.self) private var playerController: PlayerController?

    /// Clears the custom tab bar + home indicator + (when present) the floating
    /// mini-player — none of which are part of this pushed screen's safe area.
    private var bottomInset: CGFloat { playerController?.contentBottomInset ?? PlayerController.baseBottomInset }

    @ViewBuilder
    var body: some View {
        if inSheet {
            docScroll(topPadding: 24, bottomPadding: 32)
                .overlay(alignment: .topTrailing) {
                    Button { dismiss() } label: {
                        LucideIcon(.x, .md)
                            .foregroundStyle(Color.vControlLabel)
                            .frame(width: 32, height: 32)
                            // Opaque (not the translucent control fill), so the
                            // document scrolling under it doesn't show through.
                            .background(Color.vSurface, in: Circle())
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                            .padding(6) // pads the hit area out to 44pt
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                }
                .sheetBackground()
        } else {
            docScroll(topPadding: 6, bottomPadding: bottomInset)
                .appNavBar(title: doc.title) { dismiss() }
        }
    }

    private func docScroll(topPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(doc.eyebrow)
                    .font(.appFont.sectionLabel)
                    .foregroundStyle(Color.vText3)
                    .padding(.bottom, 8)

                Text(doc.title)
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.vText)
                    .padding(.bottom, 4)

                Text("Last updated: \(doc.updated)")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
                    .padding(.bottom, 28)

                ForEach(doc.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.appTitle3)
                            .foregroundStyle(Color.vText)
                        if let body = section.body {
                            bodyText(body)
                        }
                        ForEach(section.subsections, id: \.heading) { sub in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(sub.heading)
                                    .font(.appSubheadlineSemibold)
                                    .foregroundStyle(Color.vText2)
                                bodyText(sub.text)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
        .scrollIndicators(.hidden)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.appSubheadline)
            .foregroundStyle(Color.vText2)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Help Center

/// Native Help Center: the web support page's FAQ as an expandable list, plus
/// an email-support card (the web's contact form is a mailto under the hood).
struct HelpCenterScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(PlayerController.self) private var playerController
    @State private var expanded: Set<String> = []

    /// Clears the custom tab bar + home indicator + (when present) the floating
    /// mini-player — none of which are part of this pushed screen's safe area.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Quick answers to the most common questions — or reach out and we usually reply within 24 hours.")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
                    .padding(.bottom, 14)

                faqList

                contactCard
                    .padding(.top, 28)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 2)
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: "Help Center") { dismiss() }
    }

    private var faqList: some View {
        VStack(spacing: 0) {
            ForEach(Array(HelpContent.faqs.enumerated()), id: \.element.question) { index, faq in
                if index > 0 {
                    Rectangle().fill(Color.vDivider).frame(height: 1)
                }
                faqRow(faq)
            }
        }
    }

    private func faqRow(_ faq: HelpContent.FAQ) -> some View {
        let isOpen = expanded.contains(faq.question)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    if isOpen { expanded.remove(faq.question) } else { expanded.insert(faq.question) }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(faq.question)
                            // Row-title scale (like picker/sheet rows) — the
                            // 16pt body read too heavy against 14pt answers.
                            .font(.appCalloutSemibold)
                            .foregroundStyle(Color.vText)
                            .multilineTextAlignment(.leading)
                        Text(faq.category)
                            .font(.appFont.sectionLabel)
                            .foregroundStyle(Color.vText3)
                    }
                    Spacer(minLength: 8)
                    LucideIcon(.plus, .md)
                        .foregroundStyle(isOpen ? Color.vText : Color.vText3)
                        .rotationEffect(.degrees(isOpen ? 45 : 0))
                        .padding(.top, 3)
                }
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(faq.answer)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .lineSpacing(3)
                    .padding(.bottom, 16)
                    .padding(.trailing, 28)
            }
        }
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Still need help?")
                .font(.appTitle3)
                .foregroundStyle(Color.vText)
            Text("We read every message. Most replies land within 24 hours on weekdays.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            // PrimaryButton .inline metrics (42pt, appSubheadlineSemibold) with a
            // leading icon the component doesn't model.
            Button {
                openURL(URL(string: "mailto:management@volspire.com")!)
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(.mail, .sm)
                    Text("Email support").font(.appSubheadlineSemibold)
                }
                .foregroundStyle(Color.vOnInverse)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.vInverse, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

            Text("Opens your mail app addressed to management@volspire.com.")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.vSurface))
    }
}

// MARK: - Help content (copied from volspire.com/support)

enum HelpContent {
    struct FAQ {
        let question: String
        let answer: String
        let category: String
    }

    /// Marketplace & Payouts entries are hidden while monetization is off
    /// (FeatureFlags.marketplace), matching the gated marketplace UI.
    static let faqs: [FAQ] = allFaqs.filter {
        FeatureFlags.marketplace || $0.category != "Marketplace & Payouts"
    }

    private static let allFaqs: [FAQ] = [
        FAQ(
            question: "How do I upload my first track?",
            answer: "Hit the “+” button and choose “Track”. Drop in your audio file (or video for visual tracks), add a cover, set visibility, pick a genre, and publish. You can edit details any time from the track detail page.",
            category: "Uploads & Tracks"
        ),
        FAQ(
            question: "What’s the difference between Tracks, Short Tracks and Snippets?",
            answer: "Volspire splits the catalog by length so listeners always know what they’re hearing. Tracks are longer than 2:00, Short Tracks run 0:30 to 2:00, and Snippets are under 0:30. The home page surfaces a shelf for each.",
            category: "Uploads & Tracks"
        ),
        FAQ(
            question: "What audio formats are supported?",
            answer: "MP3, WAV and M4A for audio. For tracks marked as visual, MP4 video files are accepted — the audio is decoded for playback while the video frames render in the player.",
            category: "Uploads & Tracks"
        ),
        FAQ(
            question: "How do I get paid for sales?",
            answer: "You’ll need a Stripe Connect account. From Settings → Marketplace on the web, follow the onboarding flow and pick your country (this determines payout currency). Once Stripe verifies you, your sales pay out automatically on Stripe’s normal schedule.",
            category: "Marketplace & Payouts"
        ),
        FAQ(
            question: "How do refunds work?",
            answer: "For digital goods we generally don’t offer refunds, but if there’s a problem with a download or a service wasn’t delivered, contact us using the email below and we’ll review the order.",
            category: "Marketplace & Payouts"
        ),
        FAQ(
            question: "How do I share a folder with collaborators?",
            answer: "Open the folder, tap “Share”, search for the user by username, choose Editor (can upload + delete) or Viewer (read-only), and send the invite. They’ll see the folder under their workspace.",
            category: "Workspace & Collaboration"
        ),
        FAQ(
            question: "I forgot my password — how do I reset it?",
            answer: "Use the “Forgot password” link on the login screen. We’ll email a reset link to the address on file. If you don’t receive it within a couple of minutes, check spam, or reach out below.",
            category: "Account & Login"
        ),
        FAQ(
            question: "How do I delete my account?",
            answer: "Go to Settings → Manage account → Delete account — you'll confirm with your password (or by typing DELETE for social logins). Your personal account information is permanently removed or anonymized. Some content — like messages or collaborative content — may remain to preserve functionality for other users; email privacy@volspire.com and we'll remove your uploads too.",
            category: "Account & Login"
        ),
        FAQ(
            question: "Someone uploaded my track — how do I get it removed?",
            answer: "File a DMCA takedown notice by emailing management@volspire.com. Include: a link to the infringing track on Volspire, proof you own the original (release links, Soundcloud/Spotify URL, distributor metadata, etc.), your contact info, and a statement that you are the rights holder or are authorized to act on their behalf. We process valid notices within 48 hours.",
            category: "Copyright & Takedowns"
        ),
        FAQ(
            question: "What does a valid DMCA takedown notice need?",
            answer: "Per Section 8 of our Terms of Service: a description of the copyrighted work, the URL of the infringing content on Volspire, your contact information (name, address, email, phone), a good-faith statement that the use is unauthorized, a statement under penalty of perjury that the notice is accurate, and your physical or electronic signature. Send to management@volspire.com. We will not act on incomplete or anonymous notices.",
            category: "Copyright & Takedowns"
        ),
        FAQ(
            question: "My track was taken down — can I dispute it?",
            answer: "Yes. If you believe the takedown was filed in error or you are licensed to use the material, you can submit a counter-notice. Email management@volspire.com with the track URL, your full contact info, and a statement under penalty of perjury that you have a good-faith belief the content was removed by mistake. We follow standard DMCA counter-notice procedure — if the original claimant does not file suit, we may restore the content after the statutory waiting period.",
            category: "Copyright & Takedowns"
        ),
        FAQ(
            question: "How do I report harassment, abuse, or another safety issue?",
            answer: "Tap the “…” menu on any track, comment, profile, message, or listing and choose Report, then pick a reason. You can also Block someone from their profile or a conversation to instantly hide their content and stop them from contacting you. We review every report and act on violations within 24 hours. For anything urgent, you can still email management@volspire.com.",
            category: "Privacy & Safety"
        ),
    ]
}

// MARK: - Terms of Service (copied from volspire.com/terms)

extension SettingsDoc {
    static let terms = SettingsDoc(
        eyebrow: "Legal",
        title: "Terms of Service",
        updated: "July 25, 2026",
        sections: [
            Section(title: "1. Acceptance of Terms", body: """
            By creating an account or using Volspire (the "Platform"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the Platform.

            These Terms constitute a legally binding agreement between you and Volspire ("Volspire," "we," "us," or "our"). We may update these Terms from time to time. Continued use of the Platform after changes are posted constitutes your acceptance of the revised Terms.
            """),
            Section(title: "2. Eligibility", body: """
            You must be at least 13 years old to use Volspire. Children under 13 may not use the Platform under any circumstances.

            If you are under 18 (or the age of majority where you live), you may use the Platform only with the consent and involvement of a parent or legal guardian who has reviewed and agreed to these Terms on your behalf. By using the Platform, you represent and warrant that you meet these requirements and that your use of the Platform does not violate any applicable law or regulation.
            """),
            Section(title: "3. User Accounts", body: """
            You are responsible for maintaining the confidentiality of your account credentials and for all activity that occurs under your account. You agree to notify us immediately at management@volspire.com if you suspect unauthorized access to your account.

            You may not create an account on behalf of another person without their authorization, impersonate any person or entity, or use a username that is offensive, misleading, or that infringes another party's rights.

            We reserve the right to suspend or terminate accounts that violate these Terms.

            You may stop using the Platform at any time and delete your account (or request deletion) as described in our Privacy Policy. Certain content, communications, or information may remain available after deletion where necessary for platform functionality, legal obligations, or the rights of other users.
            """),
            Section(title: "4. User Content — Your Responsibility", body: """
            You are solely and entirely responsible for any content you upload, post, share, or distribute on the Platform, including audio files, video, cover art, profile information, and messages ("User Content").

            By uploading User Content, you represent and warrant that:

            • You own the content outright, or you have obtained all necessary licenses, rights, consents, and permissions to upload and distribute it on the Platform
            • Your User Content does not infringe the intellectual property rights, privacy rights, publicity rights, or any other rights of any third party
            • Your User Content complies with all applicable laws and regulations
            • You have the right to grant Volspire the license described in Section 5

            Volspire does not verify ownership or licensing of uploaded content. If you upload content you do not own or have rights to, you bear full legal and financial responsibility for any resulting claims, damages, or penalties. Volspire assumes no liability whatsoever for User Content uploaded by users.

            Volspire does not determine ownership rights, splits, credits, royalties, or licensing terms between collaborators. You are solely responsible for establishing agreements regarding ownership, compensation, attribution, and permissions with your collaborators before sharing or using collaborative works.
            """),
            Section(title: "5. License You Grant to Volspire", body: """
            By uploading User Content to the Platform, you grant Volspire a non-exclusive, worldwide, royalty-free license to host, store, reproduce, display, and distribute your User Content solely as necessary to operate and provide the Platform, including making your User Content available to other users according to the visibility settings and features you select (for example, streaming your track to listeners, displaying your cover art, or sharing a file you posted to a collaborative workspace with its members).

            This license does not transfer ownership of your content to Volspire. You retain all ownership rights in your User Content. You may delete your content at any time, which will terminate this license for that content (subject to reasonable caching and backup periods).

            If you delete your account without first deleting your content, some of your content may remain on the Platform attributed to an anonymized profile (see our Privacy Policy), and this license continues for that content until it is deleted.
            """),
            Section(title: "6. Prohibited Content", body: """
            You may not upload, post, or distribute any content that:

            • Infringes any copyright, trademark, patent, trade secret, or other intellectual property right of any party — this includes uploading music, samples, beats, or recordings that you did not create or do not hold a valid license to distribute
            • Contains unlicensed interpolations, samples, or replays of copyrighted material without clearance from the rights holder
            • Is defamatory, harassing, threatening, abusive, or discriminatory
            • Contains explicit sexual content or pornography
            • Depicts or promotes violence, self-harm, or illegal activity
            • Constitutes spam, phishing, or deceptive content
            • Contains malware, viruses, or malicious code
            • Violates the privacy of any individual (e.g., sharing personal information without consent)
            • Impersonates any person, artist, or entity in a misleading way
            • Is illegal under any applicable local, state, national, or international law

            Uploading copyrighted material without authorization is a serious violation of these Terms and of applicable copyright law, including the Digital Millennium Copyright Act (DMCA). We will respond to valid takedown notices and may remove infringing content, suspend repeat infringers, and cooperate with rights holders and law enforcement.

            ZERO TOLERANCE. Volspire has zero tolerance for objectionable content and for abusive behavior. We review reports of objectionable content — including harassment, hate speech, sexual content, content that sexualizes or endangers minors, and threats of violence — promptly, and we may remove content that violates these Terms and suspend or permanently terminate the responsible account. You can report content, or block another user, at any time from within the app.
            """),
            Section(title: "7. Content Removal and Account Suspension", body: """
            Volspire reserves the right — but is not obligated — to review, remove, or disable access to any User Content at any time, for any reason, with or without notice, including but not limited to content that we determine in our sole discretion violates these Terms, infringes third-party rights, or is otherwise harmful to users or the Platform.

            We also reserve the right to suspend or permanently terminate any account that violates these Terms, is involved in fraudulent activity, or poses a risk to the safety or integrity of the Platform. You may appeal a removal or suspension by contacting us at management@volspire.com, but we are not obligated to restore content or reinstate accounts.

            Removal of your content or termination of your account does not entitle you to a refund of any fees paid.
            """),
            Section(title: "8. DMCA and Copyright Policy", body: """
            Volspire respects intellectual property rights and expects users to do the same. If you believe that content on the Platform infringes your copyright, you may submit a DMCA takedown notice to us at management@volspire.com with the following information:

            • A description of the copyrighted work you claim has been infringed
            • A description of where the allegedly infringing content is located on the Platform
            • Your contact information (name, address, email, phone number)
            • A statement that you have a good faith belief that the use is not authorized by the copyright owner, its agent, or the law
            • A statement, under penalty of perjury, that the information in your notice is accurate and that you are the copyright owner or authorized to act on the owner's behalf
            • Your physical or electronic signature

            We will process valid notices promptly and may remove the identified content. Repeat infringers will have their accounts terminated.
            """),
            Section(title: "9. Fees and Paid Features", body: """
            Volspire is currently free to use. The Platform does not currently offer purchases, subscriptions, marketplace checkout, or payout functionality, we do not collect payment information, and no payment processor is integrated with the Platform today.

            We may introduce paid features in the future (for example, a marketplace for licensing tracks, sample packs, or creative services). If we do, any fees will be clearly disclosed before you incur them, payments will be handled by a reputable third-party payment processor under its own terms, and these Terms will be updated — with notice to you — before any paid features become available. Until such an update takes effect, nothing on the Platform requires payment.
            """),
            Section(title: "10. Disclaimer of Warranties", body: """
            The Platform is provided "as is" and "as available" without warranties of any kind, either express or implied, including but not limited to implied warranties of merchantability, fitness for a particular purpose, or non-infringement. Volspire does not warrant that the Platform will be uninterrupted, error-free, or free of viruses or other harmful components.

            We make no representations or warranties regarding the accuracy, reliability, or completeness of any content on the Platform, including User Content uploaded by other users.

            Volspire does not act as a record label, publisher, manager, agent, distributor, or licensing representative for any user unless explicitly agreed in writing, and nothing in these Terms creates any partnership, agency, employment, or professional relationship between you and Volspire.
            """),
            Section(title: "11. Limitation of Liability", body: """
            To the fullest extent permitted by applicable law, Volspire and its operators, employees, and affiliates shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including but not limited to loss of profits, data, goodwill, or other intangible losses, arising out of or relating to:

            • Your use of or inability to use the Platform
            • Any User Content uploaded by you or other users
            • Any copyright infringement or intellectual property claims arising from User Content
            • Unauthorized access to or alteration of your data
            • Any third-party conduct or content on the Platform

            In no event shall Volspire's total liability to you for all claims exceed the greater of (a) the amount you paid to Volspire in the 12 months preceding the claim or (b) one hundred dollars ($100).

            Some jurisdictions do not allow the exclusion of certain warranties or the limitation of liability for certain damages, so some of the above limitations may not apply to you.
            """),
            Section(title: "12. Indemnification", body: """
            You agree to indemnify, defend, and hold harmless Volspire and its operators, employees, and affiliates from and against any claims, liabilities, damages, losses, and expenses (including reasonable legal fees) arising out of or in any way connected with:

            • Your access to or use of the Platform
            • Your User Content, including any claim that it infringes a third party's intellectual property or other rights
            • Your violation of these Terms
            • Your violation of any applicable law or regulation

            Volspire reserves the right to assume exclusive control of any matter subject to indemnification by you, at your expense.
            """),
            Section(title: "13. Governing Law", body: """
            These Terms are governed by the laws of the State of New York, without regard to its conflict of law provisions. Any dispute arising out of or relating to these Terms or the Platform shall be resolved exclusively in the state or federal courts located in New York County, New York, and you consent to personal jurisdiction in those courts.
            """),
            Section(title: "14. Changes to These Terms", body: """
            We may modify these Terms at any time. When we make material changes, we will update the "Last updated" date and, where appropriate, notify you via email or through the Platform. Your continued use of the Platform after changes take effect constitutes your acceptance of the updated Terms.
            """),
            Section(title: "15. Apple App Store Users", body: """
            If you download or use Volspire through the Apple App Store, the following additional terms apply. These Terms are an agreement between you and Volspire only — not with Apple Inc. ("Apple"). You acknowledge that Apple is not responsible for providing maintenance or support services for the Platform, and that Apple is not responsible for any claims relating to Volspire or your use of it — including product liability claims, claims that the Platform fails to conform to any applicable legal or regulatory requirement, and claims arising under consumer protection or similar laws. In the event of any third-party claim that the Platform infringes that party's intellectual property rights, Volspire — not Apple — is responsible for the investigation, defense, settlement, and discharge of the claim.

            You represent that you are not located in a country subject to a U.S. Government embargo and that you are not on any U.S. Government list of prohibited or restricted parties. Apple and Apple's subsidiaries are third-party beneficiaries of these Terms and may enforce them against you.
            """),
            Section(title: "16. Contact Us", body: """
            If you have questions about these Terms, please contact us at:

            Volspire
            management@volspire.com
            """),
        ]
    )
}

// MARK: - Privacy Policy (copied from volspire.com/privacy)

extension SettingsDoc {
    static let privacy = SettingsDoc(
        eyebrow: "Legal",
        title: "Privacy Policy",
        updated: "July 25, 2026",
        sections: [
            Section(title: "1. Who We Are", body: """
            Volspire ("Volspire," "we," "us," or "our") is a music platform that connects artists, producers, and creative collaborators. This Privacy Policy explains how we collect, use, disclose, and safeguard information when you use our website at volspire.com and our mobile apps (together, the "Platform").

            By creating an account or using the Platform, you agree to the practices described in this Privacy Policy. If you do not agree, do not use the Platform.

            For users located in the European Economic Area, the United Kingdom, or other jurisdictions with similar data protection laws, Volspire acts as the controller of the personal information described in this Privacy Policy.
            """),
            Section(title: "2. Who Can Use Volspire", body: """
            The Platform is not directed to children under 13, and we do not permit anyone under 13 to create an account. We do not knowingly collect personal information from children under 13. If we become aware that a user is under 13, we will terminate that account and delete the associated personal information promptly. If you believe a child under 13 has created an account, please contact us at privacy@volspire.com.

            If you are between 13 and 17 (or under the age of majority where you live), you may use Volspire only with the consent and involvement of a parent or legal guardian who has agreed to our Terms of Service on your behalf.
            """),
            Section(title: "3. Information We Collect", subsections: [
                Subsection(heading: "3.1 Information You Provide Directly", text: """
                When you create an account or use the Platform, you may provide:

                • Account credentials: email address and password (passwords are hashed and never stored in plaintext)
                • Profile information: username, biography, location, profile photo and banner image, account type (artist, producer, etc.), and genre tags
                • Content: audio files, video files, cover art, and any other material you upload to the Platform
                • Communications: messages sent to other users through the Platform (see Section 7 for how messages are handled if you delete your account)
                • Payment information: none. Volspire is currently free and does not process payments — we do not collect or store payment card numbers, bank account details, or billing information. If we introduce paid features in the future, we will update this policy before any payment data is collected.
                """),
                Subsection(heading: "3.2 Information Collected Automatically", text: """
                When you use the Platform, we automatically collect a small number of event-level signals so artist dashboards, search ranking, and product improvements can work. Specifically, we record:

                • Listen analytics: when you play a track, we record the track played, your session ID, playback source, accumulated listening time, completion percentage, seek events (how often and where you skipped), and the specific segments of a track you listened to. We also log track_play, track_ended, audio_settings_changed (e.g., toggling visualizer / EQ), and playback_error events
                • Stream events: when you meet a minimum listening threshold on a track, a stream is counted and attributed to your session
                • Page views: when you navigate between pages, we log the page visited, the prior page, and a timestamp
                • Engagement events: liking or saving a track, following or unfollowing a user, posting a comment, sharing a link, performing a search, and toggling the visualizer. We log the event type, the related item ID, and your session ID
                • Approximate location: when your request reaches our servers, our hosting provider (Vercel) derives approximate geographic information from your IP address, such as country, region, city, and timezone. We attach this to the event so artists can see roughly where their listeners are. We never access your device's GPS — our apps do not request location permission — and we do not attach the IP address itself to event records (note that our hosting and database providers may retain IPs at the infrastructure layer for short periods as part of standard server access logs)
                • Device and environment: from your User-Agent and Accept-Language headers we derive a coarse device class (mobile / tablet / desktop), browser family (Chrome, Safari, Firefox, etc.), operating system family (iOS, Android, macOS, Windows, Linux), and your preferred language. We do not run advertising-grade fingerprinting libraries — only this lightweight parsing
                • Marketing attribution: if you arrive at the Platform via a link containing UTM parameters (utm_source, utm_medium, utm_campaign, utm_term, utm_content) or a referring URL, we capture those values once per session so we can understand where new users are coming from
                • Authentication cookies, tokens, and session identifiers (UUIDs) used to maintain your logged-in state
                • Push notification token: if you enable push notifications in the mobile app, we store the device push token, platform, and device model needed to deliver the alerts you opted into. You can turn notifications off at any time in the app's settings or your device settings

                We do not use third-party advertising trackers, cross-site behavioral ad networks, or browser-fingerprinting libraries. The analytics described above are collected and stored on our own infrastructure and are used solely to provide Platform features (play counts, artist analytics dashboards, search and discovery), to debug bugs and security issues, and to improve the service. We do not sell or share these signals with advertisers or data brokers.
                """),
                Subsection(heading: "3.3 Information from Third Parties", text: """
                If you sign up or log in with a third-party identity provider — Sign in with Apple or Google — that provider shares basic account information with us: your email address (or Apple's private relay address if you choose to hide your email) and, where you consent, your name. We use this information solely to create and authenticate your account, and we never receive your password from these providers.

                We do not currently receive personal information about you from any other third parties, and no payment provider is integrated with the Platform.
                """),
            ]),
            Section(title: "4. How We Use Your Information", body: """
            We use the information we collect to:

            • Create and maintain your account and profile
            • Enable core Platform features: uploading and streaming music, collaboration tools, workspace folders, and messaging
            • Provide artists with analytics about their content (plays, streams, listener behavior on their own tracks)
            • Deliver the push notifications you have enabled (new messages, activity on your content) — you can turn these off at any time
            • Detect and prevent fraud, abuse, and security incidents
            • Respond to your support requests and communications
            • Send transactional communications (account verification, password resets) — we do not send marketing emails without your explicit consent
            • Improve and develop the Platform based on aggregated, anonymized usage patterns
            • Comply with applicable legal obligations

            We do not sell your personal information. We do not use your personal information to serve third-party advertisements.
            """),
            Section(title: "5. How We Share Your Information", body: """
            We share your information only in the following circumstances:

            • Public profile information: your username, profile photo, bio, account type, and publicly posted content (tracks, packs) are visible to other users of the Platform by design
            • Service providers: we share data with Supabase (database, authentication, and file storage), Vercel (website hosting), and Apple (Push Notification service, to deliver notifications to the iOS app) solely to operate the Platform. These providers are contractually bound to protect your data and may not use it for their own marketing purposes
            • Legal compliance: we may disclose information if required by law, regulation, court order, or to protect the rights, property, or safety of Volspire, our users, or the public
            • Business transfers: if Volspire is acquired, merged, or its assets are transferred, your information may be transferred as part of that transaction. We will notify you before your data becomes subject to a materially different privacy policy
            • With your consent: for any sharing not described above, we will ask for your explicit consent first
            """),
            Section(title: "6. Third-Party Services", subsections: [
                Subsection(heading: "Supabase", text: """
                We use Supabase to store user data, authenticate accounts, and host uploaded files. Data is stored on Supabase's infrastructure. See Supabase's privacy policy at supabase.com/privacy.
                """),
                Subsection(heading: "Vercel", text: """
                We host the volspire.com website on Vercel. When your requests reach our servers, Vercel processes your IP address to serve the site and to derive the coarse location data described in Section 3.2. See Vercel's privacy policy at vercel.com/legal/privacy-policy.
                """),
                Subsection(heading: "Sign in with Apple & Google Sign-In", text: """
                If you choose social login, Apple or Google authenticates you and shares your email address (or a private relay address) and basic profile information with us, as described in Section 3.3. See apple.com/legal/privacy and policies.google.com/privacy. We do not currently use any payment processor — if paid features launch in the future, this policy will be updated first.
                """),
                Subsection(heading: "Apple Push Notification service", text: """
                Push notifications to the iOS app are delivered through Apple's Push Notification service (APNs). Apple processes your device token and the content of each notification (for example, a new-message preview) in transit. Notifications are optional — you can decline or disable them at any time. See apple.com/legal/privacy.
                """),
            ]),
            Section(title: "7. Data Retention", body: """
            We retain your personal information for as long as your account is active or as needed to provide the Platform. Specifically:

            • Account and profile data: retained until you delete your account
            • Uploaded content: retained until you delete it
            • Listen analytics and stream events: retained in session-level form to power artist dashboards and platform statistics; after you delete your account these records are no longer linked to an identifiable profile
            • Push notification tokens: kept while you are signed in with notifications enabled; deactivated when you sign out and deleted when you delete your account

            When you delete your account, your personal account information is removed or anonymized: your login credentials (email address, password, and linked Apple/Google sign-in identities) are permanently deleted and your profile is erased. Certain content, such as messages or collaborative content, may remain where necessary to preserve functionality for other users. For example, messages may remain available to the other participants in a conversation after account deletion, because removing them could affect those users' collaboration history; they are attributed to an anonymized handle rather than to your profile. You may request removal of uploaded content by contacting us at privacy@volspire.com.
            """),
            Section(title: "8. Your Rights and Choices", body: """
            Depending on where you live, you may have the following rights regarding your personal information:

            • Access: request a copy of the personal information we hold about you
            • Correction: request that we correct inaccurate or incomplete information
            • Deletion: delete your account at any time in the app (Settings → Manage account → Delete account) or on the web (Settings → Account) — your personal account information is removed or anonymized as described in Section 7. You may also email privacy@volspire.com to request account deletion or removal of uploaded content
            • Portability: request your data in a portable format
            • Opt-out of sale: we do not sell your personal information, so there is nothing to opt out of

            If you reside in a U.S. state with a comprehensive consumer privacy law — including California (CCPA/CPRA), Virginia (VCDPA), Colorado (CPA), Connecticut (CTDPA), Utah (UCPA), Texas (TDPSA), and other states with similar laws as they take effect — you may have additional rights, which may include the right to know what personal information is collected, the right to correct or delete that information, the right to opt out of certain processing or sales, and the right to non-discrimination for exercising these rights.

            To exercise any of these rights, contact us at privacy@volspire.com. We will respond within 45 days. We may need to verify your identity before fulfilling a request.
            """),
            Section(title: "9. Data Security", body: """
            We take reasonable technical and organizational measures to protect your information, including:

            • Passwords are hashed using industry-standard algorithms — we cannot retrieve your plaintext password
            • Account deletion requires fresh re-authentication (your password, or re-verifying with your sign-in provider) to prevent unauthorized deletion via a hijacked session
            • All data in transit is encrypted via HTTPS/TLS
            • Access to production data is restricted to authorized personnel

            No method of transmission or storage is 100% secure. In the event of a data breach that is likely to affect your rights, we will notify you and any required regulators as required by applicable law.
            """),
            Section(title: "10. Governing Law", body: """
            This Privacy Policy is governed by the laws of the State of New York, without regard to its conflict of law provisions. Any dispute arising under this policy will be resolved in the state or federal courts located in New York County, New York, and you consent to the personal jurisdiction of those courts.
            """),
            Section(title: "11. Changes to This Policy", body: """
            We may update this Privacy Policy from time to time. When we make material changes, we will update the "Last updated" date at the top of this page and, where appropriate, notify you by email or through the Platform. Your continued use of the Platform after changes become effective constitutes your acceptance of the revised policy.
            """),
            Section(title: "12. Contact Us", body: """
            If you have questions, concerns, or requests regarding this Privacy Policy or your personal data, please contact us at:

            Volspire
            privacy@volspire.com

            We aim to respond to all privacy-related inquiries within 5 business days.
            """),
        ]
    )
}
