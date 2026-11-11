//
//  FolderShareLinkSheet.swift
//  Volspire
//
//  A folder's public share link ("anyone with the link can view"), from the
//  folder's "…" menu or its header pill. Two states:
//  - No link: what sharing means (view-only, no account needed, private
//    tracks stay hidden), the options (downloads, expiry), then Create —
//    behind a confirm, since it makes the folder viewable outside the app.
//  - Link on: the link with Copy and its current settings (a short list), then
//    the options for the NEXT link, and Turn off link / Make new link (which
//    mints a link with those options and kills the old one). Nothing changes
//    without its confirm, and there's no separate "save".
//  Laid out like the New Folder / New Playlist forms: labelled sections,
//  field-styled cards, the Cancel + action footer.
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
        _expiry = State(initialValue: .never)
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
                } else {
                    form
                }
            }
            // The form sheets' body inset (New Folder / New Playlist).
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .animation(.easeInOut(duration: 0.2), value: link)
        }
        .selfSizedDetent()
        .sheetBackground()
        .confirmModal($confirm)
        .task { await load() }
    }

    /// The New Folder form's anatomy: labelled sections in field-styled
    /// cards, then the footer pair. No link: Cancel / Create link. Link on:
    /// Turn off link / Make new link — the options are always the NEXT
    /// link's, so there's no separate "save" (one action, one confirm).
    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let link {
                linkSection(link)
            } else {
                aboutSection
            }

            optionsSection

            if link != nil {
                CancelSendButtons(
                    sendTitle: "Make new link",
                    cancelTitle: "Turn off link",
                    cancelDestructive: true,
                    canSend: true,
                    isSending: busy,
                    onCancel: confirmTurnOff,
                    onSend: confirmNewLink
                )
                .padding(.top, 4)
            } else {
                CancelSendButtons(
                    sendTitle: "Create link",
                    canSend: true,
                    isSending: busy,
                    onCancel: { dismiss() },
                    onSend: confirmCreate
                )
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Sections

    /// No link yet: what sharing means.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetFieldLabel("Who can see it")
            VStack(alignment: .leading, spacing: 12) {
                point(.eye, "Anyone with the link can view this folder. No account needed.")
                point(.playFill, "They can play tracks and open files, but can't upload, comment or see members.")
                point(.lock, "Private tracks stay hidden. Public and unlisted tracks are included.")
            }
            .padding(14)
            .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func point(_ icon: LucideIcon.Name, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LucideIcon(icon, .sm)
                .foregroundStyle(Color.vText2)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.appSubheadline)
                .foregroundStyle(Color.vText2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Link on: the URL in a field-styled row with Copy / Share on its
    /// right, and its current settings underneath.
    private func linkSection(_ link: ApiFolderShareLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetFieldLabel("Current link")
            HStack(spacing: 4) {
                Text(link.shareURL?.absoluteString ?? "")
                    .font(.appBody)
                    .foregroundStyle(link.expired ? Color.vText3 : Color.vText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                fieldIconButton(.copy, label: "Copy link") { copy(link) }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .disabled(link.expired)
            linkStatus(link)
                .padding(.top, 4)
        }
    }

    /// The current link's settings as a short list (the "Who can see it"
    /// points' style): who can open it, downloads, expiry.
    @ViewBuilder
    private func linkStatus(_ link: ApiFolderShareLink) -> some View {
        if link.expired {
            Text("This link has expired. Make a new link to share again.")
                .font(.appFootnote)
                .foregroundStyle(Color.vError)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let expires = MessageTime.parse(link.expiresAt)
                .map { "Expires \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Never expires"
            VStack(alignment: .leading, spacing: 10) {
                point(.eye, "Anyone with the link can view")
                point(.download, link.allowDownloads ? "Downloads on" : "Downloads off")
                point(.clock, expires)
            }
            .padding(.horizontal, 4)
        }
    }

    private func fieldIconButton(_ icon: LucideIcon.Name, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, .md)
                .foregroundStyle(Color.vText2)
                .frame(width: 36, height: 36)
                .minimumHitArea(for: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Downloads + expiry for the link Create / Make new link will mint.
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetFieldLabel(link == nil ? "Options" : "New link options")
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    optionLabel(.download, "Allow downloads")
                    Spacer(minLength: 8)
                    // Empty label, like Settings — the ink style draws the
                    // label beside the switch, so a titled Toggle doubled it.
                    Toggle("", isOn: $allowDownloads)
                        .labelsHidden()
                        .toggleStyle(.ink(scale: 1.25))
                        .accessibilityLabel("Allow downloads")
                }
                .padding(.horizontal, 16)
                .frame(height: Self.optionRowHeight)

                SettingsDivider()

                // Label on its own line, the choices full width under it —
                // side by side squeezed "Expires" into two lines.
                VStack(alignment: .leading, spacing: 12) {
                    optionLabel(.clock, "Expires")
                    UploadSegmentedSwitch(
                        segments: Expiry.allCases.map { UploadSegment(value: $0, title: $0.label) },
                        selected: expiry ?? .never,
                        labelFont: .appSubheadline
                    ) { expiry = $0 }
                }
                .padding(16)
            }
            .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .disabled(busy)
        }
    }

    /// The downloads row: a touch roomier than a settings row.
    private static let optionRowHeight: CGFloat = 58

    private func optionLabel(_ icon: LucideIcon.Name, _ title: String) -> some View {
        HStack(spacing: 12) {
            LucideIcon(icon, .lg).foregroundStyle(Color.vText2)
            // Regular weight — the medium read as bold here.
            Text(title).font(.appCalloutRegular).foregroundStyle(Color.vText)
        }
    }

    // MARK: - Confirms

    private func confirmCreate() {
        confirm = DestructiveConfirm(
            icon: .link,
            title: "Make this folder viewable by anyone with the link?",
            message: "Files and tracks in “\(folderName)” will be visible to anyone you share it with. \(optionsSummary) You can turn the link off at any time.",
            actionLabel: "Create link",
            destructive: false
        ) { await create() }
    }

    private func confirmNewLink() {
        confirm = DestructiveConfirm(
            icon: .refreshCw,
            title: "Make a new link?",
            message: "The current link stops working, and anyone who has it will need the new one. \(optionsSummary)",
            actionLabel: "Make new link",
            destructive: false
        ) { await create() }
    }

    private func confirmTurnOff() {
        confirm = DestructiveConfirm(
            icon: .link,
            title: "Turn off the public link?",
            message: "Anyone using this link will lose access right away.",
            actionLabel: "Turn off"
        ) { await revoke() }
    }

    /// What the next link will be, for the confirms.
    private var optionsSummary: String {
        let downloads = allowDownloads ? "Downloads on" : "Downloads off"
        let expires = (expiry ?? .never) == .never ? "never expires" : "expires in \((expiry ?? .never).label)"
        return "The link: \(downloads.lowercased()), \(expires)."
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

    /// Takes the server's link and resets the draft to match it.
    private func apply(_ fresh: ApiFolderShareLink) {
        link = fresh
        allowDownloads = fresh.allowDownloads
        // The options are the NEXT link's; they start at Never (the live
        // link's real expiry shows in its status line).
        expiry = .never
        onChange(fresh)
    }

    private func copy(_ link: ApiFolderShareLink) {
        guard let url = link.shareURL else { return }
        UIPasteboard.general.url = url
        Haptics.success()
        ToastCenter.shared.show("Link copied")
    }

}
