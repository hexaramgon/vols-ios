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
    @Environment(PlayerController.self) private var playerController
    @Bindable var viewModel: ProfileScreenViewModel

    let userId: String

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
    @State private var errorMessage: String? = nil
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var selectedAvatarData: Data? = nil
    /// A freshly-picked avatar awaiting crop in the full-screen cropper.
    @State private var avatarCropTarget: CropTarget? = nil
    @State private var bannerItem: PhotosPickerItem? = nil
    @State private var selectedBannerData: Data? = nil
    /// A freshly-picked banner awaiting crop (at the hero's on-screen aspect).
    @State private var bannerCropTarget: CropTarget? = nil
    @State private var locationCompleter = LocationCompleter()
    @FocusState private var locationFocused: Bool

    var body: some View {
        // A pushed page (not a sheet) — back chevron pops, Save stays trailing.
        ScrollView {
            VStack(spacing: 22) {
                header
                formCard.padding(.horizontal, ViewConst.screenPaddings)
                rolesCard.padding(.horizontal, ViewConst.screenPaddings)
            }
            .padding(.bottom, bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.vBase.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(Color.vBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Edit Profile")
                    .font(.appHeadline)
                    .foregroundStyle(.white)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                BackButton(shadow: false)
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
                .foregroundStyle(hasChanges ? Color.brand : Color.vText3)
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
        .enableSwipeBack()
        // NOTE: no .preferredColorScheme here — as a pushed page it inherits
        // dark from the stack. Declaring it again made the window re-resolve
        // the scheme on pop (a whole-screen dim flash). Sheets need their own;
        // pushed pages must not.
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
        return PhotosPicker(selection: $bannerItem, matching: .images) {
            // The image lives in an overlay of a proposal-sized placeholder: a
            // `.fill` image REPORTS its covering width (~450pt for a wide banner
            // at 150pt tall), and that used to stretch the whole ScrollView
            // content wider than the screen — everything shoved off the right
            // edge. Overlays never influence layout, so this can't.
            Color.clear
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .overlay { BannerImageView(data: bannerData, url: bannerURL) }
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    EditPenPill()
                }
        }
        // Pick → crop (hero aspect) → stash. Uploads on Save, not now.
        .onChange(of: bannerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    bannerCropTarget = CropTarget(image: ui.normalizedUp())
                }
            }
        }
        .fullScreenCover(item: $bannerCropTarget) { target in
            // Crop at the hero banner band's canonical aspect (fixed ≈0.92 so
            // the stored image is identical from any device — see ProfileLayout).
            // The old wide 3:1 crop got aspect-filled into this near-square
            // box: blown up ~3× (blurry) and showing only the middle slice of
            // what was framed. 1600px keeps @3x screen widths sharp.
            ImageCropperView(
                image: target.image,
                onCrop: { data in selectedBannerData = data; bannerCropTarget = nil },
                onCancel: { bannerCropTarget = nil },
                aspectRatio: ProfileLayout.bannerCropAspect,
                outputSize: 1600,
                allowsFitMode: false
            )
        }
    }

    var avatarBlock: some View {
        // Hoisted for the same reason as `cover` — the label closure is `@Sendable`.
        let avatarData = selectedAvatarData
        let avatarURL = viewModel.profileImageURL
        return VStack(spacing: 10) {
            PhotosPicker(selection: $avatarItem, matching: .images) {
                AvatarImageView(data: avatarData, url: avatarURL)
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.vBase, lineWidth: 4))
                    .overlay(alignment: .bottomTrailing) {
                        EditPenBadge()
                    }
            }
        }
        .frame(maxWidth: .infinity)
        // Pick → crop (square) → stash. Nothing uploads until Save.
        .onChange(of: avatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    avatarCropTarget = CropTarget(image: ui.normalizedUp())
                }
            }
        }
        .fullScreenCover(item: $avatarCropTarget) { target in
            ImageCropperView(
                image: target.image,
                onCrop: { data in selectedAvatarData = data; avatarCropTarget = nil },
                onCancel: { avatarCropTarget = nil },
                allowsFitMode: false,
                showsCircularMask: true
            )
        }
    }
}

// MARK: - Form card

private extension EditProfileScreen {
    /// The same `AuthFieldGroup` rows the signup wizard uses — icon column, one
    /// grouped card, hairlines inset past the icons — rather than this screen's
    /// old labelled rows, so editing a profile looks like creating one.
    var formCard: some View {
        // One labelled section per field — they're unrelated values, so sharing
        // a single grouped card read as one control split in two.
        VStack(alignment: .leading, spacing: 22) {
            fieldSection("Username") {
                AuthRow(icon: .user, placeholder: "Username", text: $editUsername)
            }

            fieldSection("Bio") { bioRow }

            fieldSection("Location") {
                locationRow
                if showLocationSuggestions {
                    locationSuggestions
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showLocationSuggestions)
    }

    /// Section heading over its own grouped card.
    func fieldSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title)
            AuthFieldGroup { content() }
        }
    }

    /// Section heading in the wizard's voice (`appCalloutSemibold`, white).
    func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.appCalloutSemibold)
            .foregroundStyle(.white)
    }

    /// Multi-line bio in the icon-row language. Grows like the register wizard's
    /// fields rather than sitting in a fixed-height `TextEditor` well.
    var bioRow: some View {
        HStack(alignment: .top, spacing: 12) {
            LucideIcon(.squarePen, .md)
                .foregroundStyle(Color.vText3)
                .frame(height: 22) // optical align with the first text line
            TextField(
                "",
                text: $editBio,
                prompt: Text("Tell people about yourself").foregroundStyle(Color.vText3),
                axis: .vertical
            )
            .font(.appBody)
            .foregroundStyle(.white)
            .tint(.white)
            .lineLimit(2 ... 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    var showLocationSuggestions: Bool {
        locationFocused && !locationCompleter.suggestions.isEmpty
    }

    /// Mirrors the wizard's location field: pin icon that brightens on focus,
    /// 54pt row, suggestions dropping into the same card below it.
    var locationRow: some View {
        HStack(spacing: 12) {
            LucideIcon(.mapPin, .md)
                .foregroundStyle(locationFocused ? .white : Color.vText3)
            TextField(
                "",
                text: $editLocation,
                prompt: Text("City, Country").foregroundStyle(Color.vText3)
            )
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
        .padding(.horizontal, 16)
        .frame(height: 54)
        .animation(.easeInOut(duration: 0.15), value: locationFocused)
    }

    var locationSuggestions: some View {
        ForEach(locationCompleter.suggestions, id: \.self) { suggestion in
            AuthRowDivider()
            Button {
                editLocation = formatted(suggestion)
                locationCompleter.clear()
                locationFocused = false
            } label: {
                HStack(spacing: 12) {
                    LucideIcon(.mapPin, .sm)
                        .foregroundStyle(Color.vText3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title)
                            .font(.appCallout).foregroundStyle(.white).lineLimit(1)
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

    /// Condenses a completion into a "City, Region" string (drops the trailing
    /// country when a state/region is present).
    func formatted(_ suggestion: MKLocalSearchCompletion) -> String {
        let region = suggestion.subtitle
            .split(separator: ",").first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return region.isEmpty ? suggestion.title : "\(suggestion.title), \(region)"
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

}

// MARK: - Roles card

private extension EditProfileScreen {
    /// Section header + chips, laid out like the signup wizard's roles step (no
    /// surrounding card) so the two read as the same form.
    var rolesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("Your roles")
                Spacer()
                Text("\(selectedTags.count)/\(ProfileRoles.max)")
                    .font(.appFootnoteMedium)
                    .foregroundStyle(Color.vText3)
            }
            Text("Helps people find your work. Pick up to \(ProfileRoles.max).")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)

            RolePicker(selection: $selectedTags)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func save() {
        isSaving = true
        Task {
            // Deferred image uploads run now, on Save — the avatar/banner aren't
            // committed until the user taps Save. `saveProfile` then writes the
            // resulting URLs, so upload must happen first.
            if let data = selectedAvatarData {
                guard await viewModel.uploadAvatar(userId: userId, imageData: data) else {
                    isSaving = false
                    errorMessage = "Failed to upload avatar"
                    return
                }
            }
            if let data = selectedBannerData {
                guard await viewModel.uploadBanner(userId: userId, imageData: data) else {
                    isSaving = false
                    errorMessage = "Failed to upload banner"
                    return
                }
            }
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

/// The cover's edit-pen chip (struct: `LucideIcon.init` is main-actor, and
/// PhotosPicker labels are `@Sendable` — a struct's memberwise init isn't).
/// Same boxy chip language as the header pills: 11pt continuous corners,
/// solid dark fill, borderless, white icon.
private struct EditPenPill: View {
    var body: some View {
        LucideIcon(.squarePen, .sm)
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(10)
    }
}

/// The avatar's edit-pen badge — the same chip, ringed in the page colour so
/// it separates from the photo (like the avatar's own vBase ring).
private struct EditPenBadge: View {
    var body: some View {
        LucideIcon(.squarePen, .sm)
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.vBase, lineWidth: 3))
    }
}

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
