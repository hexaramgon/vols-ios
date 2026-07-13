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

    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController

    /// Clears the custom tab bar + home indicator + (when present) the floating
    /// mini-player — none of which are part of this pushed screen's safe area.
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(doc.eyebrow.uppercased())
                    .font(.appLabel)
                    .tracking(2)
                    .foregroundStyle(Color.vText3)
                    .padding(.bottom, 8)

                Text(doc.title)
                    .font(.appLargeTitle)
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)

                Text("Last updated: \(doc.updated)")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
                    .padding(.bottom, 28)

                ForEach(doc.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.appTitle3)
                            .foregroundStyle(.white)
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
            .padding(.top, 6)
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: doc.title) { dismiss() }
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
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

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
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
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
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text(faq.category.uppercased())
                            .font(.appMicroSemibold)
                            .tracking(1.5)
                            .foregroundStyle(Color.vText3)
                    }
                    Spacer(minLength: 8)
                    LucideIcon(.plus, .md)
                        .foregroundStyle(isOpen ? .white : Color.vText3)
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
                .foregroundStyle(.white)
            Text("We read every message. Most replies land within 24 hours on weekdays.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            Button {
                openURL(URL(string: "mailto:management@volspire.com")!)
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(.mail, .md)
                    Text("Email support").font(.appCalloutSemibold)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white, in: Capsule())
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

    static let faqs: [FAQ] = [
        FAQ(
            question: "How do I upload my first track?",
            answer: "Hit the “+” button and choose “Track”. Drop in your audio file (or video for visual tracks), add a cover, set visibility, pick a genre, and publish. You can edit details any time from the track detail page.",
            category: "Uploads & Tracks"
        ),
        FAQ(
            question: "What’s the difference between Tracks, Demos and Samples?",
            answer: "Volspire splits the catalog by length so listeners always know what they’re hearing. Tracks are over 2:00, Demos are between 0:30 and 2:00, and Samples are under 0:30. The home page surfaces a “Popular” shelf for each.",
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
            answer: "Email us at management@volspire.com from your account email (or use Settings → Account → Delete account on the web). Deletion is permanent and removes your tracks, packs, services, library and messages within 30 days. Past sales records are retained for tax/legal reasons but anonymized.",
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
            answer: "Email management@volspire.com and include the username, track URL, or message thread, plus a brief description of what happened. We review every report and act on policy violations — see our Terms for the full list of prohibited content.",
            category: "Privacy & Safety"
        ),
    ]
}

// MARK: - Terms of Service (copied from volspire.com/terms)

extension SettingsDoc {
    static let terms = SettingsDoc(
        eyebrow: "Legal",
        title: "Terms of Service",
        updated: "May 30, 2026",
        sections: [
            Section(title: "1. Acceptance of Terms", body: """
            By creating an account or using Volspire (the "Platform"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the Platform.

            These Terms constitute a legally binding agreement between you and Volspire ("Volspire," "we," "us," or "our"), currently operated as an unincorporated business based in New York, NY. We may update these Terms from time to time. Continued use of the Platform after changes are posted constitutes your acceptance of the revised Terms.
            """),
            Section(title: "2. Eligibility", body: """
            You must be at least 18 years old to use Volspire. By using the Platform, you represent and warrant that you are 18 or older, that you have the legal capacity to enter into these Terms, and that your use of the Platform does not violate any applicable law or regulation.
            """),
            Section(title: "3. User Accounts", body: """
            You are responsible for maintaining the confidentiality of your account credentials and for all activity that occurs under your account. You agree to notify us immediately at management@volspire.com if you suspect unauthorized access to your account.

            You may not create an account on behalf of another person without their authorization, impersonate any person or entity, or use a username that is offensive, misleading, or that infringes another party's rights.

            We reserve the right to suspend or terminate accounts that violate these Terms.
            """),
            Section(title: "4. User Content — Your Responsibility", body: """
            You are solely and entirely responsible for any content you upload, post, share, or distribute on the Platform, including audio files, video, cover art, sample packs, profile information, and messages ("User Content").

            By uploading User Content, you represent and warrant that:

            • You own the content outright, or you have obtained all necessary licenses, rights, consents, and permissions to upload and distribute it on the Platform
            • Your User Content does not infringe the intellectual property rights, privacy rights, publicity rights, or any other rights of any third party
            • Your User Content complies with all applicable laws and regulations
            • You have the right to grant Volspire the license described in Section 5

            Volspire does not verify ownership or licensing of uploaded content. If you upload content you do not own or have rights to, you bear full legal and financial responsibility for any resulting claims, damages, or penalties. Volspire assumes no liability whatsoever for User Content uploaded by users.
            """),
            Section(title: "5. License You Grant to Volspire", body: """
            By uploading User Content to the Platform, you grant Volspire a non-exclusive, worldwide, royalty-free license to host, store, reproduce, display, and distribute your User Content solely as necessary to operate and provide the Platform (for example, streaming your track to listeners, displaying your cover art, or delivering a sample pack to a buyer).

            This license does not transfer ownership of your content to Volspire. You retain all ownership rights in your User Content. You may delete your content at any time, which will terminate this license for that content (subject to reasonable caching and backup periods).
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
            """),
            Section(title: "7. Content Removal and Account Suspension", body: """
            Volspire reserves the right — but is not obligated — to review, remove, or disable access to any User Content at any time, for any reason, with or without notice, including but not limited to content that we determine in our sole discretion violates these Terms, infringes third-party rights, or is otherwise harmful to users or the Platform.

            We also reserve the right to suspend or permanently terminate any account that violates these Terms, is involved in fraudulent activity, or poses a risk to the safety or integrity of the Platform. You may appeal a removal or suspension by contacting us at management@volspire.com, but we are not obligated to restore content or reinstate accounts.

            Removal of your content or termination of your account does not entitle you to a refund of any fees paid.
            """),
            Section(title: "8. DMCA and Copyright Policy", body: """
            Volspire respects intellectual property rights and expects users to do the same. If you believe that content on the Platform infringes your copyright, you may submit a DMCA takedown notice to us at legal@volspire.com with the following information:

            • A description of the copyrighted work you claim has been infringed
            • A description of where the allegedly infringing content is located on the Platform
            • Your contact information (name, address, email, phone number)
            • A statement that you have a good faith belief that the use is not authorized by the copyright owner, its agent, or the law
            • A statement, under penalty of perjury, that the information in your notice is accurate and that you are the copyright owner or authorized to act on the owner's behalf
            • Your physical or electronic signature

            We will process valid notices promptly and may remove the identified content. Repeat infringers will have their accounts terminated.
            """),
            Section(title: "9. Payments and Marketplace", body: """
            Purchases on the Platform are processed through Stripe. By making or receiving payments, you also agree to Stripe's Terms of Service. Volspire is not a party to transactions between buyers and sellers beyond facilitating the payment infrastructure.

            For purchases of digital tracks, sample packs, and license upgrades, payments settle directly from the buyer to the seller through Stripe Connect, minus any platform fee disclosed at checkout. For purchases of creative services, payments are held by Volspire on the platform balance until the buyer accepts delivery or until seven (7) days after the seller marks the order as delivered, at which point funds are released to the seller. This buyer-protection window is designed to give buyers a reasonable opportunity to review delivered work before payouts are finalized; if the buyer takes no action, funds release automatically.

            Volspire may charge platform fees on transactions, which will be disclosed at checkout. All sales are final except as provided through Volspire's refund-request flow, which is accessible from your order history and allows buyers to request a refund subject to seller approval or, in limited circumstances, platform review.

            Sellers are solely responsible for ensuring they have the right to sell any content listed on the Platform, for the accuracy of their listings, and for fulfilling digital deliveries. Volspire is not liable for disputes between buyers and sellers, though we may, in our sole discretion, assist in resolving disputes.

            You are solely responsible for any tax obligations arising from payments you receive through the Platform. Stripe may be required by law to issue IRS Form 1099-K to sellers who meet applicable reporting thresholds (currently $600 or more in gross payments per calendar year). To facilitate this, Stripe collects tax identification information (such as SSN or EIN) during the Connect onboarding process. You are responsible for providing accurate tax information to Stripe and for reporting and paying all applicable taxes on your earnings. Volspire does not provide tax advice — consult a qualified tax professional if you have questions about your obligations.
            """),
            Section(title: "10. Disclaimer of Warranties", body: """
            The Platform is provided "as is" and "as available" without warranties of any kind, either express or implied, including but not limited to implied warranties of merchantability, fitness for a particular purpose, or non-infringement. Volspire does not warrant that the Platform will be uninterrupted, error-free, or free of viruses or other harmful components.

            We make no representations or warranties regarding the accuracy, reliability, or completeness of any content on the Platform, including User Content uploaded by other users.
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
            Section(title: "15. Contact Us", body: """
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
        updated: "May 30, 2026",
        sections: [
            Section(title: "1. Who We Are", body: """
            Volspire ("Volspire," "we," "us," or "our") is a music platform that connects artists, producers, and creative collaborators. Volspire is currently operated as an unincorporated business based in New York, NY. This Privacy Policy explains how we collect, use, disclose, and safeguard information when you use our website and platform at volspire.com (the "Platform").

            By creating an account or using the Platform, you agree to the practices described in this Privacy Policy. If you do not agree, do not use the Platform.
            """),
            Section(title: "2. Who Can Use Volspire", body: """
            The Platform is intended solely for users who are 18 years of age or older. By using Volspire, you represent and warrant that you are at least 18 years old. We do not knowingly collect personal information from anyone under 18. If we become aware that a user is under 18, we will terminate that account and delete the associated data promptly. If you believe a minor has created an account, please contact us at management@volspire.com.
            """),
            Section(title: "3. Information We Collect", subsections: [
                Subsection(heading: "3.1 Information You Provide Directly", text: """
                When you create an account or use the Platform, you may provide:

                • Account credentials: email address and password (passwords are hashed and never stored in plaintext)
                • Profile information: username, display name, biography, location, profile photo, account type (artist, producer, etc.), and genre tags
                • Content: audio files, video files, cover art, sample packs, and any other material you upload to the Platform
                • Communications: messages sent to other users through the Platform
                • Payment information: when you make or receive payments, you interact directly with Stripe. Volspire does not receive or store your full card number, CVV, or bank account details. We store only your Stripe customer ID and transaction metadata.
                """),
                Subsection(heading: "3.2 Information Collected Automatically", text: """
                When you use the Platform, we automatically collect a small number of event-level signals so artist dashboards, search ranking, and product improvements can work. Specifically, we record:

                • Listen analytics: when you play a track, we record the track played, your session ID, playback source, accumulated listening time, completion percentage, seek events (how often and where you skipped), and the specific segments of a track you listened to. We also log track_play, track_ended, audio_settings_changed (e.g., toggling visualizer / EQ), and playback_error events
                • Stream events: when you meet a minimum listening threshold on a track, a stream is counted and attributed to your session
                • Page views: when you navigate between pages, we log the page visited, the prior page, and a timestamp
                • Engagement events: liking or saving a track / pack / service, following or unfollowing a user, posting a comment, sharing a link, performing a search, toggling the visualizer, and initiating or completing a purchase. We log the event type, the related item ID, and your session ID
                • Geolocation (coarse and precise): when your request reaches our servers, our hosting provider (Vercel) provides country, region, city, timezone, and approximate latitude/longitude derived from your IP address. We attach this geo data to the event so artists can see roughly where their listeners are. We do not attach the IP address itself to event records (note that our hosting and database providers may retain IPs at the infrastructure layer for short periods as part of standard server access logs)
                • Device and environment: from your User-Agent and Accept-Language headers we derive a coarse device class (mobile / tablet / desktop), browser family (Chrome, Safari, Firefox, etc.), operating system family (iOS, Android, macOS, Windows, Linux), and your preferred language. We do not run advertising-grade fingerprinting libraries — only this lightweight parsing
                • Marketing attribution: if you arrive at the Platform via a link containing UTM parameters (utm_source, utm_medium, utm_campaign, utm_term, utm_content) or a referring URL, we capture those values once per session so we can understand where new users are coming from
                • Authentication tokens and session identifiers (UUIDs) used to maintain your logged-in state

                We do not use third-party advertising trackers, cross-site behavioral ad networks, or browser-fingerprinting libraries. The analytics described above are collected and stored on our own infrastructure and are used solely to provide Platform features (play counts, artist analytics dashboards, search and discovery), to debug bugs and security issues, and to improve the service. We do not sell or share these signals with advertisers or data brokers.
                """),
                Subsection(heading: "3.3 Information from Third Parties", text: """
                If you connect a Stripe account to receive payouts as a seller or artist, Stripe may share onboarding status, payout eligibility, account balance, transaction-related metadata (such as charges, refunds, transfers, and disputes), and outstanding account requirements with us. We do not receive your full financial account details (full card number, full bank account number, or government-issued identification images) from Stripe. Please review Stripe's Privacy Policy at stripe.com/privacy for details on how Stripe handles your data.
                """),
            ]),
            Section(title: "4. How We Use Your Information", body: """
            We use the information we collect to:

            • Create and maintain your account and profile
            • Enable core Platform features: uploading and streaming music, collaboration tools, workspace folders, messaging, and the marketplace
            • Process purchases and payouts through Stripe
            • Provide artists with analytics about their content (plays, streams, listener behavior on their own tracks)
            • Detect and prevent fraud, abuse, and security incidents
            • Respond to your support requests and communications
            • Send transactional communications (account verification, purchase receipts, password resets) — we do not send marketing emails without your explicit consent
            • Improve and develop the Platform based on aggregated, anonymized usage patterns
            • Comply with applicable legal obligations

            We do not sell your personal information. We do not use your personal information to serve third-party advertisements.
            """),
            Section(title: "5. How We Share Your Information", body: """
            We share your information only in the following circumstances:

            • Public profile information: your username, profile photo, bio, account type, and publicly posted content (tracks, packs) are visible to other users of the Platform by design
            • Service providers: we share data with Supabase (database, authentication, and file storage) and Stripe (payment processing and payouts) solely to operate the Platform. These providers are contractually bound to protect your data and may not use it for their own marketing purposes
            • Legal compliance: we may disclose information if required by law, regulation, court order, or to protect the rights, property, or safety of Volspire, our users, or the public
            • Business transfers: if Volspire is acquired, merged, or its assets are transferred, your information may be transferred as part of that transaction. We will notify you before your data becomes subject to a materially different privacy policy
            • With your consent: for any sharing not described above, we will ask for your explicit consent first
            """),
            Section(title: "6. Third-Party Services", subsections: [
                Subsection(heading: "Supabase", text: """
                We use Supabase to store user data, authenticate accounts, and host uploaded files. Data is stored on Supabase's infrastructure. See Supabase's privacy policy at supabase.com/privacy.
                """),
                Subsection(heading: "Stripe", text: """
                We use Stripe to process payments and facilitate payouts to creators via Stripe Connect. When you make a purchase or connect a payout account, you are subject to Stripe's privacy policy at stripe.com/privacy. Card data is transmitted directly to Stripe and never passes through Volspire's servers.
                """),
            ]),
            Section(title: "7. Data Retention", body: """
            We retain your personal information for as long as your account is active or as needed to provide the Platform. Specifically:

            • Account and profile data: retained until you delete your account
            • Uploaded content: retained until you delete it or delete your account
            • Listen analytics and stream events: retained in aggregated and session-level form to power artist dashboards; raw session data may be retained for up to 24 months
            • Payment records: retained for up to 7 years as required by tax and financial record-keeping laws, even after account deletion

            When you delete your account, we permanently delete your profile, credentials, and uploaded content. Some anonymized or aggregated data (e.g., total stream counts attributed to a track) may persist as it is no longer personally identifiable.
            """),
            Section(title: "8. Your Rights and Choices", body: """
            Depending on where you live, you may have the following rights regarding your personal information:

            • Access: request a copy of the personal information we hold about you
            • Correction: request that we correct inaccurate or incomplete information
            • Deletion: delete your account at any time from Settings → Account. This permanently removes your profile, credentials, and content. You may also contact us at management@volspire.com to request deletion
            • Portability: request your data in a portable format
            • Opt-out of sale: we do not sell your personal information, so there is nothing to opt out of

            If you reside in a U.S. state with a comprehensive consumer privacy law — including California (CCPA/CPRA), Virginia (VCDPA), Colorado (CPA), Connecticut (CTDPA), Utah (UCPA), Texas (TDPSA), and other states with similar laws as they take effect — you may have additional rights, which may include the right to know what personal information is collected, the right to correct or delete that information, the right to opt out of certain processing or sales, and the right to non-discrimination for exercising these rights.

            To exercise any of these rights, contact us at management@volspire.com. We will respond within 45 days. We may need to verify your identity before fulfilling a request.
            """),
            Section(title: "9. Data Security", body: """
            We take reasonable technical and organizational measures to protect your information, including:

            • Passwords are hashed using industry-standard algorithms — we cannot retrieve your plaintext password
            • Account deletion requires password re-verification to prevent unauthorized deletion via a hijacked session
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
            management@volspire.com

            We aim to respond to all privacy-related inquiries within 5 business days.
            """),
        ]
    )
}
