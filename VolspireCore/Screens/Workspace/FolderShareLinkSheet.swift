//
//  FolderShareLinkSheet.swift
//  Volspire
//
//  A folder's public share link ("anyone with the link can view"), from the
//  folder's "…" menu or its header pill. Two states:
//  - No link: what sharing means (view-only, no account needed, private
//    tracks stay hidden), the options (downloads, expiry), then Create —
//    behind a confirm, since it makes the folder viewable outside the app.
//  - Link on: the link with Copy / Share, its status, the same options
//    (applied live), Make a new link (kills the old one) and Turn off link.
//  The server owns the token (create/update/revoke_folder_share_link);
//  visitors open it on the web, which the `shared-folder` edge function
//  serves with short-lived signed links.
//

import DesignSystem
import Services
import SharedUtilities
import SwiftUI

struct FolderShareLinkSheet: View {
    let folderId: String
    let folderName: String
    /// The link as the folder screen knows it (nil = none / not loaded).
    let initialLink: ApiFolderShareLink?
    /// Every change to the link — the folder header's "Public link" pill.
    let onChange: (ApiFolderShareLink?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link: ApiFolderShareLink?
    @State private var loaded = false
    @State private var busy = false
    @State private var allowDownloads = false
    @State private var expiry: Expiry? = .never
    @State private var confirm: DestructiveConfirm?
    private let service = SupabaseService()

    init(folderId: String, folderName: String, initialLink: ApiFolderShareLink?,
         onChange: @escaping (ApiFolderShareLink?) -> Void) {
        self.folderId = folderId
        self.folderName = folderName
        self.initialLink = initialLink
        self.onChange = onChange
        _link = State(initialValue: initialLink)
        _loaded = State(initialValue: initialLink != nil)
        _allowDownloads = State(initialValue: initialLink?.allowDownloads ?? false)
        _expiry = State(initialValue: initialLink.map { $0.expiresAt == nil ? .never : nil } ?? .never)
    }

    /// How long a link lasts. A link's expiry counts from when it's set, so a
    /// running link with an expiry shows no pill selected until one is picked.
    enum Expiry: CaseIterable, Identifiable {
        case never, week, month
        var id: Self { self }
        var label: String {
            switch self {
            case .never: "Never"
            case .week: "7 days"
            case .month: "30 days"
            }
        }
        /// On a live link the choice resets the expiry from today.
        var resetLabel: String {
            switch self {
            case .never: "Never"
            case .week: "In 7 days"
            case .month: "In 30 days"
            }
        }
        var days: Int? {
            switch self {
            case .never: nil
            case .week: 7
            case .month: 30
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .link, title: link == nil ? "Share a public link" : "Public link",
                        subtitle: folderName) { dismiss() }

            Group {
                if !loaded {
                    ProgressView().tint(Color.vText3)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if let link {
                    manage(link)
                } else {
                    explainer
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .animation(.easeInOut(duration: 0.2), value: link)
        }
        .selfSizedDetent()
        .sheetBackground()
        .confirmModal($confirm)
        .task { await load() }
    }

    // MARK: - No link yet

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                point(.eye, "Anyone with the link can view this folder. No account needed.")
                point(.playFill, "They can play tracks and open files, but can't upload, comment or see members.")
                point(.lock, "Private tracks stay hidden. Public and unlisted tracks are included.")
            }

            options

            PrimaryButton("Create link", icon: .link, busy: busy) {
                confirm = DestructiveConfirm(
                    icon: .link,
                    title: "Make this folder viewable by anyone with the link?",
                    message: "Files and tracks in “\(folderName)” will be visible to anyone you share it with. You can turn the link off at any time.",
                    actionLabel: "Create link",
                    destructive: false
                ) { await create() }
            }
        }
    }

    private func point(_ icon: LucideIcon.Name, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LucideIcon(icon, .sm)
                .foregroundStyle(Color.vText2)
                .frame(width: 28, height: 28)
                .background(Color.vControl, in: Circle())
            Text(text)
                .font(.appSubheadline)
                .foregroundStyle(Color.vText2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Link on

    private func manage(_ link: ApiFolderShareLink) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // The link, with its status under it, in one card.
            HStack(spacing: 12) {
                LucideIcon(.link, .md)
                    .foregroundStyle(Color.vText2)
                    .frame(width: 36, height: 36)
                    .background(Color.vControl, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.shareURL?.absoluteString ?? "")
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(link.expired ? Color.vText3 : Color.vText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(status(link))
                        .font(.appFootnote)
                        .foregroundStyle(link.expired ? Color.vError : Color.vText3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            HStack(spacing: 8) {
                // The members sheet's Invite pill (the standard capsule).
                Button { copy(link) } label: {
                    CapsuleButtonLabel(icon: .copy, title: "Copy link", expands: true)
                }
                .buttonStyle(.plain)
                Button { share(link) } label: {
                    CapsuleButtonLabel(icon: .share2, title: "Share…", style: .secondary, expands: true)
                }
                .buttonStyle(.plain)
            }
            .disabled(link.expired)
            .opacity(link.expired ? 0.4 : 1)

            options

            VStack(spacing: 0) {
                OptionSheetRow(icon: .refreshCw, title: "Make a new link") {
                    confirm = DestructiveConfirm(
                        icon: .refreshCw,
                        title: "Make a new link?",
                        message: "The current link stops working. Anyone who has it will need the new one.",
                        actionLabel: "Make new link",
                        destructive: false
                    ) { await create() }
                }
                OptionSheetRow(icon: .x, title: "Turn off link", tint: .vDestructive) {
                    confirm = DestructiveConfirm(
                        icon: .link,
                        title: "Turn off the public link?",
                        message: "Anyone using this link will lose access right away.",
                        actionLabel: "Turn off"
                    ) { await revoke() }
                }
            }
            .padding(.horizontal, -20)
        }
    }

    /// Under the link. Expiry and downloads live in the options below, so
    /// this only says who can open it (or that it's expired).
    private func status(_ link: ApiFolderShareLink) -> String {
        link.expired ? "This link has expired. Make a new link to share again."
            : "Anyone with the link can view"
    }

    // MARK: - Options (draft before a link exists, applied live after)

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            ComposerHeading(title: "Link options")
            VStack(spacing: 0) {
                Button {
                    Haptics.selection()
                    let on = !allowDownloads
                    withAnimation(.easeInOut(duration: 0.18)) { allowDownloads = on }
                    if link != nil { Task { await update(allowDownloads: on) } }
                } label: {
                    HStack(spacing: 12) {
                        optionLabel(.download, "Allow downloads")
                        Spacer(minLength: 8)
                        UploadSwitch(isOn: allowDownloads)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(allowDownloads ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)

                SettingsDivider()

                // With a live link: its real expiry on the right, and the
                // choices read "In 7 days" — they reset it from today.
                // Before one exists they're the new link's setting.
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        optionLabel(.clock, "Expires")
                        Spacer(minLength: 8)
                        if let current = currentExpiryLabel {
                            Text(current.text)
                                .font(.appSubheadline)
                                .foregroundStyle(current.expired ? Color.vError : Color.vText2)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(Expiry.allCases) { option in
                            Button {
                                Haptics.selection()
                                expiry = option
                                if link != nil { Task { await update(expiry: option) } }
                            } label: {
                                CapsuleButtonLabel(title: link == nil ? option.label : option.resetLabel,
                                                   style: expiry == option ? .primary : .secondary,
                                                   expands: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(expiry == option ? .isSelected : [])
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .disabled(busy)
    }

    /// The live link's expiry, e.g. "Nov 13" / "Never" / "Expired"; nil
    /// before a link exists.
    private var currentExpiryLabel: (text: String, expired: Bool)? {
        guard let link else { return nil }
        if link.expired { return ("Expired", true) }
        if let date = MessageTime.parse(link.expiresAt) {
            return (date.formatted(.dateTime.month(.abbreviated).day()), false)
        }
        return ("Never", false)
    }

    private func optionLabel(_ icon: LucideIcon.Name, _ title: String) -> some View {
        HStack(spacing: 12) {
            LucideIcon(icon, .md).foregroundStyle(Color.vText2)
            Text(title).font(.appSubheadlineMedium).foregroundStyle(Color.vText)
        }
    }

    // MARK: - Actions

    private func load() async {
        defer { loaded = true }
        do {
            if let fresh = try await service.getFolderShareLink(folderId: folderId) {
                apply(fresh)
            } else {
                link = nil
                onChange(nil)
            }
        } catch {
            // Keep what the folder screen passed in; actions will retry.
            debugLog("[FolderShareLink] load failed: \(error)")
        }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do {
            let fresh = try await service.createFolderShareLink(
                folderId: folderId, allowDownloads: allowDownloads, expiresInDays: (expiry ?? .never).days
            )
            apply(fresh)
            Haptics.success()
            if let url = fresh.shareURL {
                UIPasteboard.general.url = url
                ToastCenter.shared.show("Link created and copied")
            }
        } catch {
            debugLog("[FolderShareLink] create failed: \(error)")
            ToastCenter.shared.show("Couldn't create the link. Try again.", style: .error)
        }
    }

    private func update(allowDownloads: Bool? = nil, expiry: Expiry? = nil) async {
        let before = link
        do {
            let fresh = try await service.updateFolderShareLink(
                folderId: folderId,
                allowDownloads: allowDownloads,
                expiresInDays: expiry?.days,
                clearExpiry: expiry == .never
            )
            apply(fresh)
        } catch {
            debugLog("[FolderShareLink] update failed: \(error)")
            if let before { apply(before) }
            ToastCenter.shared.show("Couldn't update the link. Try again.", style: .error)
        }
    }

    private func revoke() async {
        busy = true
        defer { busy = false }
        do {
            try await service.revokeFolderShareLink(folderId: folderId)
            link = nil
            onChange(nil)
            ToastCenter.shared.show("Public link turned off")
        } catch {
            debugLog("[FolderShareLink] revoke failed: \(error)")
            ToastCenter.shared.show("Couldn't turn off the link. Try again.", style: .error)
        }
    }

    private func apply(_ fresh: ApiFolderShareLink) {
        link = fresh
        allowDownloads = fresh.allowDownloads
        if fresh.expiresAt == nil { expiry = .never }
        onChange(fresh)
    }

    private func copy(_ link: ApiFolderShareLink) {
        guard let url = link.shareURL else { return }
        UIPasteboard.general.url = url
        Haptics.success()
        ToastCenter.shared.show("Link copied")
    }

    private func share(_ link: ApiFolderShareLink) {
        guard let url = link.shareURL else { return }
        AnalyticsService.shared?.log(.shareClicked, metadata: ["kind": "folder_link", "method": "share_sheet"])
        UIApplication.presentActivitySheet([url])
    }
}
