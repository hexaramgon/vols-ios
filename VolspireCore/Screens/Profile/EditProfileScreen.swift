//
//  EditProfileScreen.swift
//  Volspire
//
//  The profile edit form, mirroring the web's Settings → Profile: photos
//  (banner + overlapping avatar), basic info, roles, and Save in the header.
//  Saves via `update_user`. (The Collab-map opt-in lives in Settings → Privacy.)
//

import DesignSystem
import Kingfisher
import MapKit
import PhotosUI
import SwiftUI

struct EditProfileScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(FeedStore.self) private var feedStore
    @Environment(PlayerController.self) private var playerController
    @Bindable var viewModel: ProfileScreenViewModel

    let userId: String
    /// Band title — "Edit profile" from the profile page, "Profile" when
    /// pushed from Settings.
    var title: String = "Edit profile"

    /// Clears the floating tab bar + (when present) the mini-player docked
    /// above it — same formula as Library / Messages / MediaCollection.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

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
    @State private var saved = false
    @State private var errorMessage: String? = nil
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var selectedAvatarData: Data? = nil
    /// Already uploaded for the picked photo — a retried Save (after a failed
    /// one) reuses it instead of uploading again.
    @State private var uploadedAvatarURL: URL? = nil
    @State private var uploadedBannerURL: URL? = nil
    /// A freshly-picked avatar awaiting crop in the full-screen cropper.
    @State private var avatarCropTarget: CropTarget? = nil
    @State private var bannerItem: PhotosPickerItem? = nil
    @State private var selectedBannerData: Data? = nil
    /// A freshly-picked banner awaiting crop (at the hero's on-screen aspect).
    @State private var bannerCropTarget: CropTarget? = nil
    @State private var locationCompleter = LocationCompleter()
    @FocusState private var focusedField: Field?
    /// Live availability for an edited username — same states and debounce as
    /// the signup wizard, so a taken handle is caught here instead of coming
    /// back as a save failure from the `users_username_key` unique index.
    @State private var usernameStatus: RegisterViewModel.UsernameStatus = .idle
    @State private var usernameCheck: Task<Void, Never>?

    private enum Field: Hashable { case username, bio, location }


    var body: some View {
        // A pushed page laid out like the web's Settings → Profile: Photos,
        // Basic info, Roles. Save lives in the header.
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                SettingsGroup(title: "Photos", bare: true) { photos }
                SettingsGroup(title: "Basic info", bare: true) { basicInfo }
                SettingsGroup(
                    title: "Roles",
                    caption: "Pick up to \(ProfileRoles.max). They show on your profile and filter you in Collab.",
                    bare: true
                ) {
                    RolePicker(selection: $selectedTags)
                }
                if let errorMessage {
                    ErrorBanner(errorMessage)
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 16)
            .padding(.bottom, bottomInset + 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .appNavBar(title: title, onBack: { dismiss() }) {
            saveButton
        }
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

    /// Same rule the signup wizard enforces, so a handle can't be edited into a
    /// shape that signup would have rejected.
    private var usernameValid: Bool {
        RegisterViewModel.isValidUsername(editUsername)
    }

    /// Blocks Save on a known-bad handle. An unresolved check (`.idle` after a
    /// network failure) still saves — the server has the final say via the
    /// unique index, and `saveProfile` names that error.
    private var canSave: Bool {
        hasChanges && usernameValid && usernameStatus != .taken && usernameStatus != .checking
    }

    /// Normalizes as you type exactly like the signup wizard (lowercase, spaces
    /// to underscores — the save path lowercases anyway, so doing it here just
    /// stops the field from showing something you won't get) and re-checks
    /// availability on the same 500ms debounce.
    private func usernameChanged(_ raw: String) {
        editUsername = RegisterViewModel.normalizeUsername(raw)
        usernameCheck?.cancel()
        let candidate = editUsername
        // Your own current handle is always fine — checking it would report it
        // taken by you.
        guard candidate != originalUsername, candidate.count >= 3 else {
            usernameStatus = .idle
            return
        }
        usernameStatus = .checking
        usernameCheck = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let available = await viewModel.isUsernameAvailable(candidate)
            guard !Task.isCancelled, candidate == editUsername else { return }
            switch available {
            case true: usernameStatus = .available
            case false: usernameStatus = .taken
            case nil: usernameStatus = .idle
            }
        }
    }

    /// Taken / available, sliding in on the pop marks' spring (same as sign-up).
    private var usernameStatusLine: some View {
        Group {
            switch usernameStatus {
            case .taken:
                statusText("That username is already taken.", color: .vError)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            case .available:
                statusText("Username is available.", color: .vSuccessText)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            case .checking, .idle:
                EmptyView()
            }
        }
        .animation(.popMark, value: usernameStatus)
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.appCaption)
            .foregroundStyle(color)
    }
}

// MARK: - Photos (banner + overlapping avatar)

private extension EditProfileScreen {
    var photos: some View {
        VStack(alignment: .leading, spacing: 12) {
            if FeatureFlags.profileBanners {
                ZStack(alignment: .bottomLeading) {
                    cover
                        .padding(.bottom, 40)
                    avatarBlock
                        .padding(.leading, 16)
                }
            } else {
                // Banners are parked — just the photo.
                avatarBlock
            }
            Text(FeatureFlags.profileBanners
                 ? "How the top of your profile looks. Tap the banner or your photo to change it."
                 : "Tap your photo to change it.")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var cover: some View {
        // Hoisted: the PhotosPicker label closure is `@Sendable`, so it can't
        // read main-actor view state directly — capture plain values instead.
        let bannerData = selectedBannerData
        let bannerURL = viewModel.bannerImageURL
        return PhotosPicker(selection: $bannerItem, matching: .images) {
            // The image lives in an overlay of a proposal-sized placeholder: a
            // `.fill` image REPORTS its covering width (~450pt for a wide banner
            // at 150pt tall), and that used to stretch the whole ScrollView
            // content wider than the screen — everything shoved off the right
            // edge. Overlays never influence layout, so this can't.
            Color.clear
                // The stored banner's own 16:9 shape (shared with the web).
                .aspectRatio(ProfileLayout.bannerCropAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { BannerImageView(data: bannerData, url: bannerURL) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .accessibilityLabel(bannerURL == nil && bannerData == nil ? "Add a banner" : "Change banner")
        // Pick → crop (16:9 banner) → stash. Uploads on Save, not now.
        .onChange(of: bannerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    bannerCropTarget = CropTarget(image: ui.normalizedUp())
                }
                // Cleared so picking the same photo again (after a cancelled
                // crop) is still a change.
                bannerItem = nil
            }
        }
        .fullScreenCover(item: $bannerCropTarget) { target in
            // Crop at the shared 16:9 banner aspect (same as the web), with
            // guides for what the iPhone hero and the desktop web show — see
            // ProfileLayout.
            ImageCropperView(
                image: target.image,
                onCrop: { data in
                    selectedBannerData = data
                    uploadedBannerURL = nil
                    bannerCropTarget = nil
                },
                onCancel: { bannerCropTarget = nil },
                aspectRatio: ProfileLayout.bannerCropAspect,
                // 2400×1350: tall enough for the iPhone hero's height fill
                // (~1130px at 3x) without upscaling.
                outputSize: ProfileLayout.bannerOutputSize,
                allowsFitMode: false,
                guides: ProfileLayout.bannerGuides
            )
        }
    }

    var avatarBlock: some View {
        // Hoisted for the same reason as `cover` — the label closure is `@Sendable`.
        let avatarData = selectedAvatarData
        let avatarURL = viewModel.profileImageURL
        let initial = String(editUsername.prefix(1)).uppercased()
        return PhotosPicker(selection: $avatarItem, matching: .images) {
            AvatarImageView(data: avatarData, url: avatarURL, initial: initial)
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .padding(4)
                .background(Color.vBase, in: Circle())
        }
        .accessibilityLabel("Change profile photo")
        // Pick → crop (square) → stash. Nothing uploads until Save.
        .onChange(of: avatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    avatarCropTarget = CropTarget(image: ui.normalizedUp())
                }
                // Cleared so picking the same photo again (after a cancelled
                // crop) is still a change.
                avatarItem = nil
            }
        }
        .fullScreenCover(item: $avatarCropTarget) { target in
            ImageCropperView(
                image: target.image,
                onCrop: { data in
                    selectedAvatarData = data
                    uploadedAvatarURL = nil
                    avatarCropTarget = nil
                },
                onCancel: { avatarCropTarget = nil },
                allowsFitMode: false,
                showsCircularMask: true
            )
        }
    }
}

// MARK: - Basic info

private extension EditProfileScreen {
    var basicInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsField(label: "Username") {
                HStack(spacing: 4) {
                    Text("@").foregroundStyle(Color.vText3)
                    TextField(
                        "",
                        text: Binding(get: { editUsername }, set: { usernameChanged($0) }),
                        prompt: Text("yourname").foregroundStyle(Color.vText3)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                }
                .settingsFieldStyle(focused: focusedField == .username, invalid: usernameStatus == .taken)
                usernameStatusLine
            }

            SettingsField(label: "Bio") {
                TextField(
                    "",
                    text: $editBio,
                    prompt: Text("Tell people about yourself…").foregroundStyle(Color.vText3),
                    axis: .vertical
                )
                .lineLimit(3 ... 6)
                .focused($focusedField, equals: .bio)
                .settingsFieldStyle(focused: focusedField == .bio)
                // Scalar-counted (InputLimits), matching the DB's
                // `users_bio_max_length` check.
                .charLimited($editBio, InputLimits.bio)
                Text("\(editBio.limitCount)/\(InputLimits.bio)")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            SettingsField(
                label: "Location",
                hint: "Shown on your profile, and on the Collab map if you're open to collaboration."
            ) {
                VStack(spacing: 0) {
                    locationRow
                    if showLocationSuggestions {
                        locationSuggestions
                    }
                }
                .background(
                    focusedField == .location ? Color.vFieldFocus : Color.vField,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                )
                .animation(.easeInOut(duration: 0.15), value: showLocationSuggestions)
            }
        }
    }

    var showLocationSuggestions: Bool {
        focusedField == .location && !locationCompleter.suggestions.isEmpty
    }

    var locationRow: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $editLocation,
                prompt: Text("City, Country").foregroundStyle(Color.vText3)
            )
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .tint(Color.vText)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .location)
            .charLimited($editLocation, InputLimits.location, singleLine: true)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var locationSuggestions: some View {
        ForEach(locationCompleter.suggestions, id: \.self) { suggestion in
            SettingsDivider()
            Button {
                editLocation = formatted(suggestion).capped(at: InputLimits.location)
                locationCompleter.clear()
                focusedField = nil
            } label: {
                HStack(spacing: 12) {
                    LucideIcon(.mapPin, .sm)
                        .foregroundStyle(Color.vText3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title)
                            .font(.appSubheadline).foregroundStyle(Color.vText).lineLimit(1)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
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

    /// Condenses a completion into a "City, Region" string (drops the trailing
    /// country when a state/region is present).
    func formatted(_ suggestion: MKLocalSearchCompletion) -> String {
        let region = suggestion.subtitle
            .split(separator: ",").first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return region.isEmpty ? suggestion.title : "\(suggestion.title), \(region)"
    }

    func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(.circleX, .md)
                .foregroundStyle(Color.vText3)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Save

private extension EditProfileScreen {
    /// The header's Save: ink when there's an edit to save, greyed out
    /// otherwise; a spinner while saving, then a check for a moment.
    var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving {
                    ProgressView().controlSize(.small).tint(Color.vText)
                } else if saved {
                    SuccessMark(size: 22)
                } else {
                    Text("Save")
                        .font(.appCalloutSemibold)
                        .foregroundStyle(canSave ? Color.vText : Color.vText4)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canSave || isSaving)
        .animation(.easeInOut(duration: 0.18), value: canSave)
        .accessibilityLabel(saved ? "Saved" : "Save")
    }

    func save() {
        isSaving = true
        errorMessage = nil
        Task {
            // Deferred image uploads run now, on Save — the avatar/banner aren't
            // committed until the user taps Save. `saveProfile` then writes the
            // resulting URLs, so upload must happen first.
            if let data = selectedAvatarData, uploadedAvatarURL == nil {
                guard let url = await viewModel.uploadAvatar(userId: userId, imageData: data) else {
                    isSaving = false
                    errorMessage = "Failed to upload your photo. Please try again."
                    return
                }
                uploadedAvatarURL = url
            }
            if let data = selectedBannerData, uploadedBannerURL == nil {
                guard let url = await viewModel.uploadBanner(userId: userId, imageData: data) else {
                    isSaving = false
                    errorMessage = "Failed to upload your banner. Please try again."
                    return
                }
                uploadedBannerURL = url
            }
            let username = editUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let bio = editBio.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = editLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            let success = await viewModel.saveProfile(
                userId: userId,
                username: username,
                bio: bio,
                location: location,
                tags: selectedTags,
                avatarURL: uploadedAvatarURL,
                bannerURL: uploadedBannerURL
            )
            guard success else {
                isSaving = false
                errorMessage = viewModel.profileUpdateError ?? "Failed to save profile. Please try again."
                return
            }
            selectedAvatarData = nil
            selectedBannerData = nil
            uploadedAvatarURL = nil
            uploadedBannerURL = nil
            // City changed → the Collab map is stale.
            let mapChanged = location != originalLocation
            originalUsername = username
            originalBio = bio
            originalLocation = location
            originalTags = selectedTags
            if mapChanged {
                Task { await feedStore.refreshLocationsAfterProfileChange() }
            }
            isSaving = false
            saved = true
            // Every own-profile screen refetches, then the form closes so you
            // land back on the updated profile (a beat to see the check).
            NotificationCenter.default.post(name: .ownProfileUpdated, object: nil)
            try? await Task.sleep(for: .milliseconds(500))
            dismiss()
        }
    }
}

// MARK: - Media subviews (structs so they're usable inside PhotosPicker labels)

private struct AvatarImageView: View {
    let data: Data?
    let url: URL?
    let initial: String

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else if let url {
                KFImage(url).downsampled(to: 120).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.vSurface2
                    Text(initial.isEmpty ? "?" : initial)
                        .font(.appTitle)
                        .foregroundStyle(Color.vText3)
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
                LinearGradient(colors: [.vSurface, .vCardSolid], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        HStack(spacing: 8) {
                            LucideIcon(.image, .lg)
                            Text("Add a banner").font(.appCaptionMedium)
                        }
                        .foregroundStyle(Color.vText4)
                    }
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
