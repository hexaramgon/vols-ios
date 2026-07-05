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
        .environment(\.colorScheme, .dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetBackground()
        .task { await viewModel.loadMyTracksForCollab(currentUserId: currentUserId) }
    }
}

// MARK: - Header

private extension CollabRequestSheet {
    @ViewBuilder
    var targetAvatar: some View {
        Group {
            if let url = viewModel.profileImageURL {
                KFImage(url).downsampled(to: 36).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Text(username.first.map { String($0).uppercased() } ?? "?")
                        .font(.appSubheadlineBold).foregroundStyle(Color.vText3)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }
}

// MARK: - Message + tracks

private extension CollabRequestSheet {
    func sectionLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.appCaption2Semibold).tracking(0.6).foregroundStyle(.white.opacity(0.45))
            Text("(optional)").font(.appCaption2).foregroundStyle(.white.opacity(0.25))
        }
    }

    var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("YOUR PITCH")
            TextField(
                "",
                text: $viewModel.collabMessage,
                prompt: Text("Hey \(displayName), I'd love to collaborate on a project…")
                    .foregroundColor(Color.vText3),
                axis: .vertical
            )
            .font(.appCalloutRegular)
            .foregroundStyle(.white)
            .tint(.white)
            .lineLimit(3 ... 6)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vBorder))
        }
    }

    var tracksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("ATTACH PORTFOLIO TRACKS")
                Spacer(minLength: 0)
                Text("\(attachmentsUsed)/\(viewModel.maxCollabAttachments)")
                    .font(.appMicroMedium).monospacedDigit().foregroundStyle(.white.opacity(0.35))
            }
            Text("Only your public tracks can be attached.")
                .font(.appCaption2).foregroundStyle(.white.opacity(0.3))

            if viewModel.isFetchingMyCollabTracks {
                ProgressView().tint(.white.opacity(0.5))
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
            LucideIcon(.search, .sm).foregroundStyle(.white.opacity(0.4))
            TextField("", text: $viewModel.collabTrackQuery,
                      prompt: Text("Search your tracks…").foregroundColor(.white.opacity(0.35)))
                .font(.appFootnote).foregroundStyle(.white).tint(.white)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08)))
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
                Text(track.title).font(.appSubheadlineMedium).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? Color.white : Color.clear)
                        .frame(width: 20, height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(selected ? Color.white : Color.white.opacity(0.25)))
                    if selected { LucideIcon(.check, .xs).foregroundStyle(.black) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.white.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                Text("Cancel").font(.appCallout).foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.sendCollab(userId: userId) }
            } label: {
                Group {
                    if viewModel.isSendingCollab {
                        ProgressView().tint(.black)
                    } else {
                        HStack(spacing: 7) {
                            LucideIcon(.handshake, .sm)
                            Text("Send Request").font(.appCalloutSemibold)
                        }
                        .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(viewModel.canSendCollab ? Color.white : Color.white.opacity(0.3), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSendCollab)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color.white.opacity(0.04))
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5), alignment: .top)
    }

    var successState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 60, height: 60)
                LucideIcon(.check, .xl).foregroundStyle(Color.green)
            }
            VStack(spacing: 4) {
                Text("Request sent!").font(.appTitle3Bold).foregroundStyle(.white)
                Text("Your collab request is in \(displayName)'s inbox.")
                    .font(.appSubheadline).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            }
            Button {
                dismiss()
                router.navigateToMessages()
            } label: {
                HStack(spacing: 6) {
                    Text("Open Messages").font(.appCalloutSemibold)
                    LucideIcon(.chevronRight, .sm)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}
