//
//  EditProfileScreen.swift
//  Volspire
//
//  Dark, grouped-card edit form mirroring the web settings: avatar + cover,
//  username, bio, location, and up to 3 role tags. Saves via `update_user`.
//

import DesignSystem
import Kingfisher
import MapKit
import PhotosUI
import SwiftUI

struct EditProfileScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileScreenViewModel

    let userId: String

    @State private var editUsername: String = ""
    @State private var editBio: String = ""
    @State private var editLocation: String = ""
    @State private var selectedTags: [String] = []
    // Snapshot of the loaded values so Save only enables on an actual edit.
    @State private var originalUsername: String = ""
    @State private var originalBio: String = ""
    @State private var originalLocation: String = ""
    @State private var originalTags: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var selectedAvatarData: Data? = nil
    @State private var isUploadingAvatar = false
    @State private var bannerItem: PhotosPickerItem? = nil
    @State private var selectedBannerData: Data? = nil
    @State private var isUploadingBanner = false
    @State private var locationCompleter = LocationCompleter()
    @FocusState private var locationFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    formCard.padding(.horizontal, ViewConst.screenPaddings)
                    rolesCard.padding(.horizontal, ViewConst.screenPaddings)
                }
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.vBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(white: 0.1), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Profile")
                        .font(.appHeadline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.appBody)
                        .foregroundStyle(Color.vText2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save").font(.appHeadline)
                        }
                    }
                    .disabled(isSaving || !hasChanges)
                    .foregroundStyle(hasChanges ? .white : Color.vText3)
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
        .preferredColorScheme(.dark)
        .onAppear {
            editUsername = viewModel.username
            editBio = viewModel.bio
            editLocation = viewModel.location
            selectedTags = viewModel.tags
            originalUsername = viewModel.username
            originalBio = viewModel.bio
            originalLocation = viewModel.location
            originalTags = viewModel.tags
        }
    }

    /// Save only enables once the form differs from the loaded profile (or a new
    /// avatar/banner was picked).
    private var hasChanges: Bool {
        editUsername != originalUsername
            || editBio != originalBio
            || editLocation != originalLocation
            || Set(selectedTags) != Set(originalTags)
            || selectedAvatarData != nil
            || selectedBannerData != nil
    }
}

// MARK: - Header (cover + avatar)

private extension EditProfileScreen {
    var header: some View {
        VStack(spacing: 0) {
            cover
            avatarBlock.padding(.top, -48)
        }
    }

    var cover: some View {
        // Hoisted: the PhotosPicker label closure is `@Sendable`, so it can't
        // read main-actor view state directly — capture plain values instead.
        let bannerData = selectedBannerData
        let bannerURL = viewModel.bannerImageURL
        let uploading = isUploadingBanner
        return PhotosPicker(selection: $bannerItem, matching: .images) {
            BannerImageView(data: bannerData, url: bannerURL)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.fill").font(.system(size: 11))
                        Text(uploading ? "Uploading…" : "Edit cover").font(.appFootnoteSemibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.5), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                    .padding(12)
                }
        }
        .disabled(isUploadingBanner)
        .onChange(of: bannerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    selectedBannerData = data
                    isUploadingBanner = true
                    let ok = await viewModel.uploadBanner(userId: userId, imageData: data)
                    isUploadingBanner = false
                    if !ok { errorMessage = "Failed to upload banner"; selectedBannerData = nil }
                }
            }
        }
    }

    var avatarBlock: some View {
        // Hoisted for the same reason as `cover` — the label closure is `@Sendable`.
        let avatarData = selectedAvatarData
        let avatarURL = viewModel.profileImageURL
        let uploading = isUploadingAvatar
        return VStack(spacing: 10) {
            PhotosPicker(selection: $avatarItem, matching: .images) {
                AvatarImageView(data: avatarData, url: avatarURL)
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.vBase, lineWidth: 4))
                    .overlay(alignment: .bottomTrailing) {
                        ZStack {
                            if uploading {
                                ProgressView().tint(.black).scaleEffect(0.6)
                            } else {
                                Image(systemName: "camera.fill").font(.system(size: 12)).foregroundStyle(.black)
                            }
                        }
                        .frame(width: 30, height: 30)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(Color.vBase, lineWidth: 3))
                    }
            }

            PhotosPicker(selection: $avatarItem, matching: .images) {
                Text("Edit photo").font(.appCalloutSemibold).foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(isUploadingAvatar)
        .onChange(of: avatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    selectedAvatarData = data
                    isUploadingAvatar = true
                    let ok = await viewModel.uploadAvatar(userId: userId, imageData: data)
                    isUploadingAvatar = false
                    if !ok { errorMessage = "Failed to upload avatar"; selectedAvatarData = nil }
                }
            }
        }
    }
}

// MARK: - Form card

private extension EditProfileScreen {
    var formCard: some View {
        VStack(spacing: 0) {
            inputRow("Username", text: $editUsername, prefix: "@", placeholder: "username", capitalize: false)
            rowDivider
            locationRow
            if showLocationSuggestions {
                rowDivider
                locationSuggestions
            }
            rowDivider
            multilineRow("Bio", text: $editBio, placeholder: "Tell people about yourself")
        }
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.15), value: showLocationSuggestions)
    }

    var showLocationSuggestions: Bool {
        locationFocused && !locationCompleter.suggestions.isEmpty
    }

    var locationRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("Location")
            HStack(spacing: 8) {
                TextField("City, Country", text: $editLocation)
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($locationFocused)
                    .onChange(of: editLocation) { _, newValue in
                        locationCompleter.update(newValue)
                    }
                if !editLocation.isEmpty {
                    clearButton {
                        editLocation = ""
                        locationCompleter.clear()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    var locationSuggestions: some View {
        VStack(spacing: 0) {
            ForEach(locationCompleter.suggestions, id: \.self) { suggestion in
                Button {
                    editLocation = formatted(suggestion)
                    locationCompleter.clear()
                    locationFocused = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.vText3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title)
                                .font(.appCalloutRegular).foregroundStyle(.white).lineLimit(1)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.appFootnote).foregroundStyle(Color.vText3).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Condenses a completion into a "City, Region" string (drops the trailing
    /// country when a state/region is present).
    func formatted(_ suggestion: MKLocalSearchCompletion) -> String {
        let region = suggestion.subtitle
            .split(separator: ",").first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return region.isEmpty ? suggestion.title : "\(suggestion.title), \(region)"
    }

    var rowDivider: some View {
        Rectangle().fill(.white.opacity(0.06)).frame(height: 1).padding(.leading, 16)
    }

    func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.appFootnoteSemibold)
            .foregroundStyle(Color.vText3)
            .tracking(0.6)
    }

    func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.vText3)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    func inputRow(_ label: String, text: Binding<String>, prefix: String? = nil,
                  placeholder: String = "", capitalize: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel(label)
            HStack(spacing: 2) {
                if let prefix {
                    Text(prefix).font(.appBody).foregroundStyle(Color.vText2)
                }
                TextField(placeholder, text: text)
                .font(.appBody)
                .foregroundStyle(.white)
                .tint(.white)
                .autocorrectionDisabled(!capitalize)
                .textInputAutocapitalization(capitalize ? .sentences : .never)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    func multilineRow(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                fieldLabel(label)
                Spacer()
                if !text.wrappedValue.isEmpty {
                    clearButton { text.wrappedValue = "" }
                }
            }
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.appBody).foregroundStyle(Color.vText3)
                        .padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: text)
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .frame(minHeight: 78)
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - Roles card

private extension EditProfileScreen {
    var rolesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                fieldLabel("Roles")
                Spacer()
                Text("\(selectedTags.count)/\(ProfileRoles.max)")
                    .font(.appFootnoteMedium)
                    .foregroundStyle(Color.vText3)
            }
            ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(ProfileRoles.all, id: \.self) { role in
                    roleChip(role)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    func roleChip(_ role: String) -> some View {
        let selected = selectedTags.contains(role)
        let disabled = !selected && selectedTags.count >= ProfileRoles.max
        return Button {
            if selected {
                selectedTags.removeAll { $0 == role }
            } else if selectedTags.count < ProfileRoles.max {
                selectedTags.append(role)
            }
        } label: {
            Text(role)
                .font(.appCallout)
                .foregroundStyle(selected ? .black : (disabled ? Color.vText3 : .white))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? Color.white : Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    func save() {
        isSaving = true
        Task {
            let success = await viewModel.saveProfile(
                userId: userId,
                username: editUsername.trimmingCharacters(in: .whitespaces).lowercased(),
                bio: editBio.trimmingCharacters(in: .whitespaces),
                location: editLocation.trimmingCharacters(in: .whitespaces),
                tags: selectedTags
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

// MARK: - Media subviews (structs so they're usable inside PhotosPicker labels)

private struct AvatarImageView: View {
    let data: Data?
    let url: URL?

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else if let url {
                KFImage(url).downsampled(to: 120).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.vSurface
                    Image(systemName: "person.fill").font(.system(size: 36)).foregroundStyle(Color.vText3)
                }
            }
        }
    }
}

private struct BannerImageView: View {
    let data: Data?
    let url: URL?

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else if let url {
                KFImage(url).downsampled(to: 450).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(white: 0.16), .vBase], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

// MARK: - Location autocomplete

/// Thin wrapper around `MKLocalSearchCompleter` that publishes address
/// completions as the user types. No location permission required.
@Observable
final class LocationCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Restrict completions to city / region level — no street addresses,
        // postal codes, or neighbourhoods.
        if #available(iOS 18.0, *) {
            completer.addressFilter = MKAddressFilter(
                including: [.locality, .administrativeArea, .subAdministrativeArea, .country]
            )
        }
    }

    func update(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { suggestions = []; return }
        completer.queryFragment = trimmed
    }

    func clear() { suggestions = [] }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = Array(completer.results.prefix(6))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
