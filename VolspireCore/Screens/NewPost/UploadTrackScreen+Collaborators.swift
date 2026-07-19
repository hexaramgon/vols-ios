//
//  UploadTrackScreen+Collaborators.swift
//  Volspire
//
//  Collaborator picker and the tags section.
//

import CoreTransferable
import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension UploadTrackScreen {
    // MARK: - Collaborators (picked from your collaborators — the same
    // get_my_collaborators list the folder member picker uses)

    var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Collaborators")

            Text("Tag everyone involved. They'll be credited and the track appears on their profile.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            HStack(spacing: 8) {
                Text("@")
                    .font(.appBody)
                    .foregroundStyle(Color.vText3)
                TextField(
                    "",
                    text: $viewModel.collabQuery,
                    prompt: Text("Search collaborators…").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($collabFocused)
                .onChange(of: collabFocused) { _, focused in
                    viewModel.collabFocusChanged(focused)
                }
                .onChange(of: viewModel.collabQuery) { _, _ in
                    viewModel.collabQueryChanged()
                }
                if viewModel.isSearchingCollabs {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.vText3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .uploadFieldShell()

            if collabFocused, !viewModel.isSearchingCollabs, viewModel.collabResults.isEmpty {
                Text(viewModel.hasNoCollaborators
                    ? "People you've collabed with show up here once a collab request is accepted."
                    : "No collaborators match “\(viewModel.collabQuery)”.")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
            }

            if !viewModel.collabResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(viewModel.collabResults) { user in
                        let alreadyAdded = viewModel.credits.contains { $0.userId == user.userId }
                        Button {
                            viewModel.addCredit(user)
                        } label: {
                            HStack(spacing: 12) {
                                avatarCircle(initial: user.username?.prefix(1).uppercased() ?? "?")
                                Text("@\(user.username ?? "user")")
                                    .font(.appSubheadline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(alreadyAdded ? "Added" : "Add")
                                    .font(.appFootnote)
                                    .foregroundStyle(alreadyAdded ? Color.vText3 : Color.vText2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(alreadyAdded)
                        if user.userId != viewModel.collabResults.last?.userId {
                            Rectangle().fill(Color.vBorder).frame(height: 1)
                        }
                    }
                }
                .uploadFieldShell()
            }

            ForEach(viewModel.credits) { credit in
                HStack(spacing: 12) {
                    avatarCircle(initial: credit.username.prefix(1).uppercased())

                    Text("@\(credit.username)")
                        .font(.appBodyMedium)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Menu {
                        ForEach(collaboratorRoles, id: \.self) { role in
                            Button(role) {
                                viewModel.updateCreditRole(credit.userId, role: role)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(credit.role)
                                .font(.appFootnote)
                            LucideIcon(.chevronDown, .xs)
                        }
                        .foregroundStyle(Color.vText2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(UploadTheme.border, lineWidth: 1))
                        .contentShape(.rect)
                    }

                    Button {
                        viewModel.removeCredit(credit.userId)
                    } label: {
                        LucideIcon(.x, .sm)
                            .foregroundStyle(Color.vText3)
                            .frame(width: 36, height: 36)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.vBorder, lineWidth: 1)
                )
            }
        }
    }

    func avatarCircle(initial: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
            Circle()
                .strokeBorder(Color.vBorder, lineWidth: 1)
            Text(initial)
                .font(.appLabel)
                .foregroundStyle(Color.vText2)
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - Tags

    var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Tags")
            UploadTagInput(tags: $viewModel.tags, suggestions: tagSuggestions)
        }
    }

}
