//
//  CollabRequestSheet.swift
//  Volspire
//
//  Compose-and-send a collaboration request to an artist — mirrors the web's
//  CollabModal (`send_collab_request`): an optional pitch + up to 3 attached
//  portfolio tracks, then a "request sent" success state.
//

import DesignSystem
import Kingfisher
import SwiftUI

struct CollabRequestSheet: View {
    @Bindable var viewModel: ProfileScreenViewModel
    let userId: String
    let username: String
    let currentUserId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    private var displayName: String { username.isEmpty ? "this artist" : "@\(username)" }
    private var attachmentsUsed: Int { viewModel.selectedCollabTrackIds.count }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Collab Request", subtitle: displayName, onClose: { dismiss() }) {
                targetAvatar
            }

            if viewModel.collabRequestSent {
                successState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        messageSection
                        tracksSection
                        if let err = viewModel.collabError { ErrorBanner(err) }
                    }
                    .padding(20)
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .sheetBackground()
        .task { await viewModel.loadMyTracksForCollab(currentUserId: currentUserId) }
    }
}

// MARK: - Header

private extension CollabRequestSheet {
    var targetAvatar: some View {
        AvatarView(url: viewModel.profileImageURL, name: username, size: 36)
    }
}

// MARK: - Message + tracks

private extension CollabRequestSheet {
    func sectionLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.appLabel).foregroundStyle(Color.vText2)
            Text("(optional)").font(.appCaption).foregroundStyle(Color.vText4)
        }
    }

    var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Your pitch")
            TextField(
                "",
                text: $viewModel.collabMessage,
                prompt: Text("Hey \(displayName), I'd love to collaborate on a project…")
                    .foregroundColor(Color.vText3),
                axis: .vertical
            )
            .font(.appCalloutRegular)
            .foregroundStyle(Color.vText)
            .tint(Color.vText)
            .lineLimit(3 ... 6)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    var tracksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Attach portfolio tracks")
                Spacer(minLength: 0)
                Text("\(attachmentsUsed)/\(viewModel.maxCollabAttachments)")
                    .font(.appCaption).monospacedDigit().foregroundStyle(Color.vText3)
            }
            Text("Only your public tracks can be attached.")
                .font(.appCaption).foregroundStyle(Color.vText3)

            if viewModel.isFetchingMyCollabTracks {
                ProgressView().tint(Color.vText3)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else if viewModel.myCollabTracks.isEmpty {
                Text("You have no public tracks to attach.")
                    .font(.appFootnote).foregroundStyle(Color.vText3)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 16)
            } else {
                trackSearchField
                VStack(spacing: 2) {
                    ForEach(viewModel.filteredCollabTracks) { trackRow($0) }
                }
            }
        }
    }

    var trackSearchField: some View {
        HStack(spacing: 8) {
            LucideIcon(.search, .sm).foregroundStyle(Color.vText3)
            TextField("", text: $viewModel.collabTrackQuery,
                      prompt: Text("Search your tracks…").foregroundColor(Color.vText3))
                .font(.appFootnote).foregroundStyle(Color.vText).tint(Color.vText)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    func trackRow(_ track: ProfileTrack) -> some View {
        let selected = viewModel.selectedCollabTrackIds.contains(track.id)
        let capped = !selected && attachmentsUsed >= viewModel.maxCollabAttachments
        return Button {
            viewModel.toggleCollabTrack(track.id)
        } label: {
            HStack(spacing: 11) {
                ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: 8)
                    .frame(width: 38, height: 38)
                Text(track.title).font(.appFont.trackTitle).foregroundStyle(Color.vTextRow).lineLimit(1)
                Spacer(minLength: 8)
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? Color.vInverse : Color.clear)
                        .frame(width: 20, height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(selected ? Color.vInverse : Color.ink(0.25)))
                    if selected { LucideIcon(.check, .xs).foregroundStyle(Color.vOnInverse) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.vRowActive : Color.clear, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .opacity(capped ? 0.4 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(capped)
    }
}

// MARK: - Footer + success

private extension CollabRequestSheet {
    var footer: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Text("Cancel").font(.appCallout).foregroundStyle(Color.vControlLabel)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color.vControl, in: Capsule())
            }
            .buttonStyle(.plain)

            // PrimaryButton metrics (.full: 52pt, appHeadline, dim-disabled) with
            // a custom icon label — keep in step with the component.
            Button {
                Task { await viewModel.sendCollab(userId: userId) }
            } label: {
                Group {
                    if viewModel.isSendingCollab {
                        ProgressView().tint(Color.vOnColor)
                    } else {
                        HStack(spacing: 7) {
                            LucideIcon(.send, .sm)
                            Text("Send Request").font(.appHeadline)
                        }
                        .foregroundStyle(Color.vOnColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.vAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSendCollab || viewModel.isSendingCollab)
            .opacity(viewModel.canSendCollab || viewModel.isSendingCollab ? 1 : 0.3)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .overlay(Rectangle().fill(Color.vSurface2).frame(height: 1), alignment: .top)
    }

    var successState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.vSuccessText.opacity(0.12)).frame(width: 60, height: 60)
                LucideIcon(.check, .xl).foregroundStyle(Color.vSuccessText)
            }
            VStack(spacing: 4) {
                Text("Request sent!").font(.appTitle3Bold).foregroundStyle(Color.vText)
                Text("Your collab request is in \(displayName)'s inbox.")
                    .font(.appSubheadline).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            }
            // PrimaryButton .inline metrics (42pt, appSubheadlineSemibold) with a
            // trailing chevron the component doesn't model.
            Button {
                dismiss()
                router.navigateToMessages()
            } label: {
                HStack(spacing: 6) {
                    Text("Open Messages").font(.appSubheadlineSemibold)
                    LucideIcon(.chevronRight, .sm)
                }
                .foregroundStyle(Color.vOnInverse)
                .frame(height: 42)
                .padding(.horizontal, 24)
                .background(Color.vInverse, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}
