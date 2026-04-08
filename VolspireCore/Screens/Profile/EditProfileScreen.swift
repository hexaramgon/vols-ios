//
//  EditProfileScreen.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import PhotosUI
import SwiftUI

struct EditProfileScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileScreenViewModel

    let userId: String

    @State private var editUsername: String = ""
    @State private var editBio: String = ""
    @State private var editLocation: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var selectedAvatarData: Data? = nil
    @State private var isUploadingAvatar = false
    @State private var bannerItem: PhotosPickerItem? = nil
    @State private var selectedBannerData: Data? = nil
    @State private var isUploadingBanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Banner
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let data = selectedBannerData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 140)
                                    .clipped()
                            } else if let bannerURL = viewModel.bannerImageURL {
                                KFImage(bannerURL)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 140)
                                    .clipped()
                            } else {
                                Color(.systemGray5)
                                    .frame(height: 140)
                            }
                        }

                        PhotosPicker(selection: $bannerItem, matching: .images) {
                            ZStack {
                                if isUploadingBanner {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                        }
                        .disabled(isUploadingBanner)
                        .padding(12)
                        .onChange(of: bannerItem) { _, newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    selectedBannerData = data
                                    isUploadingBanner = true
                                    let success = await viewModel.uploadBanner(userId: userId, imageData: data)
                                    isUploadingBanner = false
                                    if !success {
                                        errorMessage = "Failed to upload banner"
                                        selectedBannerData = nil
                                    }
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, ViewConst.screenPaddings)

                    // Avatar
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let data = selectedAvatarData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else if let profileURL = viewModel.profileImageURL {
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

                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            ZStack {
                                if isUploadingAvatar {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .background(Color.brand)
                            .clipShape(Circle())
                        }
                        .disabled(isUploadingAvatar)
                        .onChange(of: avatarItem) { _, newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    selectedAvatarData = data
                                    isUploadingAvatar = true
                                    let success = await viewModel.uploadAvatar(userId: userId, imageData: data)
                                    isUploadingAvatar = false
                                    if !success {
                                        errorMessage = "Failed to upload avatar"
                                        selectedAvatarData = nil
                                    }
                                }
                            }
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
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
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
        Task {
            let success = await viewModel.updateProfile(
                userId: userId,
                username: editUsername.trimmingCharacters(in: .whitespaces),
                bio: editBio.trimmingCharacters(in: .whitespaces),
                location: editLocation.trimmingCharacters(in: .whitespaces)
            )
            isSaving = false
            if success {
                dismiss()
            } else {
                errorMessage = viewModel.profileUpdateError ?? "Failed to save profile"
            }
        }
    }
}
