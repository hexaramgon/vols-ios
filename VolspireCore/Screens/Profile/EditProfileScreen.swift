//
//  EditProfileScreen.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import SwiftUI

struct EditProfileScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileScreenViewModel

    @State private var editUsername: String = ""
    @State private var editBio: String = ""
    @State private var editLocation: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Banner
                    ZStack(alignment: .bottomTrailing) {
                        if let bannerURL = viewModel.bannerImageURL {
                            KFImage(bannerURL)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 140)
                                .clipped()
                        } else {
                            Color(.systemGray5)
                                .frame(height: 140)
                        }

                        Button {
                            // TODO: pick banner image
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, ViewConst.screenPaddings)

                    // Avatar
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let profileURL = viewModel.profileImageURL {
                                KFImage(profileURL)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundStyle(Color(.systemGray3))
                            }
                        }
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())

                        Button {
                            // TODO: pick profile image
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.brand)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, -50)
                    .padding(.bottom, -8)

                    // Form fields
                    VStack(spacing: 20) {
                        editField(label: "Username", text: $editUsername)
                        editField(label: "Bio", text: $editBio, isMultiline: true)
                        editField(label: "Location", text: $editLocation)
                    }
                    .padding(.horizontal, ViewConst.screenPaddings)

                    Spacer().frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .gradientBackground()
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                    .foregroundStyle(Color.brand)
                }
            }
        }
        .onAppear {
            editUsername = viewModel.username
            editBio = viewModel.bio
            editLocation = viewModel.location
        }
    }

    private func editField(label: String, text: Binding<String>, isMultiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if isMultiline {
                TextEditor(text: text)
                    .font(.system(size: 15))
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                TextField(label, text: text)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func save() {
        isSaving = true
        // Update local viewModel immediately
        viewModel.username = editUsername
        viewModel.bio = editBio
        viewModel.location = editLocation

        // TODO: persist to Supabase
        // try await supabaseService.updateProfile(...)

        isSaving = false
        dismiss()
    }
}
