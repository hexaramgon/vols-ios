//
//  UploadTrackScreen.swift
//  Volspire
//
//

import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct UploadTrackScreen: View {
    @State var viewModel: UploadTrackViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAudioPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedVideo: PhotosPickerItem?

    private var headerTitle: String {
        switch viewModel.postType {
        case "sample_pack": "Sample Pack"
        case "skill_highlight": "Skill Highlight"
        default: "Track"
        }
    }



    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            header

            // MARK: - Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    coverAndMediaSection
                    detailsSection
                    collaboratorsSection
                    rightsSection
                    uploadButton
                        .padding(.top, 28)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
            }
        }
        .gradientBackground()
        .fileImporter(
            isPresented: $showAudioPicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.handleAudioFile(result: .success(url))
            } else if case .failure(let error) = result {
                viewModel.handleAudioFile(result: .failure(error))
            }
        }
        .onChange(of: selectedVideo) { _, newValue in
            Task {
                if let newValue,
                   let data = try? await newValue.loadTransferable(type: Data.self)
                {
                    let fileName = "video_\(UUID().uuidString).mov"
                    viewModel.handleVideoData(data, fileName: fileName)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let newValue,
                   let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)
                {
                    viewModel.handleCoverImage(image)
                }
            }
        }
        .onChange(of: viewModel.uploadState) { _, newValue in
            if newValue == .success {
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Circle())
            }

            Spacer()

            Text("New \(headerTitle)")
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            // Balance spacer
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    // MARK: - Cover + Media

    private var coverAndMediaSection: some View {
        VStack(spacing: 16) {
            // Cover art
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    if let img = viewModel.coverImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [Color.brand.opacity(0.15), Color.brand.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(Color.brand)
                                Text("Add Cover Art")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.brand)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)

            // Media type picker
            HStack(spacing: 8) {
                mediaChip("Audio", icon: "waveform", selected: viewModel.mediaType == .audio) {
                    viewModel.mediaType = .audio
                }
                mediaChip("Video", icon: "video", selected: viewModel.mediaType == .video) {
                    viewModel.mediaType = .video
                }
            }

            // File row
            if viewModel.mediaType == .audio {
                fileAttachmentRow(
                    icon: "waveform",
                    name: viewModel.audioFileName,
                    placeholder: "Attach audio file",
                    attached: viewModel.audioData != nil
                ) { showAudioPicker = true }
            } else {
                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    fileAttachmentContent(
                        icon: "video",
                        name: viewModel.videoFileName,
                        placeholder: "Choose video from library",
                        attached: viewModel.videoData != nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Details")

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Give it a name", text: $viewModel.title)
                    .font(.system(size: 16))
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Description
            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Tell people about this...", text: $viewModel.description, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Tags
            VStack(alignment: .leading, spacing: 6) {
                Text("Tags")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Hip-Hop, Trap, R&B...", text: $viewModel.tags)
                    .font(.system(size: 16))
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Collaborators

    private var collaboratorsSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Collaborators")

            // Existing
            ForEach(viewModel.collaborators) { collab in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.brand.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.brand)
                        }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(collab.role)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.brand)
                            .textCase(.uppercase)
                        Text(collab.name)
                            .font(.system(size: 15))
                    }

                    Spacer()

                    Button {
                        viewModel.removeCollaborator(collab.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Role chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(collaboratorRoles, id: \.self) { role in
                        Button {
                            viewModel.newCollaboratorRole = role
                        } label: {
                            Text(role)
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    viewModel.newCollaboratorRole == role
                                        ? Color.brand : Color(.secondarySystemGroupedBackground)
                                )
                                .foregroundStyle(
                                    viewModel.newCollaboratorRole == role ? .white : .secondary
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Name + add
            HStack(spacing: 10) {
                TextField("Name", text: $viewModel.newCollaboratorName)
                    .font(.system(size: 15))
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    viewModel.addCollaborator()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            (!viewModel.newCollaboratorRole.isEmpty
                                && !viewModel.newCollaboratorName
                                    .trimmingCharacters(in: .whitespaces).isEmpty)
                                ? Color.brand : Color(.systemGray3)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(
                    viewModel.newCollaboratorRole.isEmpty
                        || viewModel.newCollaboratorName
                            .trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
    }

    // MARK: - Rights & Distribution Card

    private var rightsSection: some View {
        VStack(spacing: 20) {
            sectionHeader("Rights & Distribution")
            licenseSection
            distributionTogglesSection
            monetizationSection
            privacySection
        }
    }

    // MARK: - License Section

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("License")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(LicenseType.allCases, id: \.self) { license in
                licenseRow(license)
            }
        }
    }

    @ViewBuilder
    private func licenseRow(_ license: LicenseType) -> some View {
        let isSelected = viewModel.licenseType == license
        Button {
            viewModel.licenseType = license
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.brand : Color(.systemGray3),
                            lineWidth: 2
                        )
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(license.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(license.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.graySecondary)
                }
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.brand.opacity(0.08) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.brand.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Distribution Toggles

    private var distributionTogglesSection: some View {
        VStack(spacing: 0) {
            toggleRow("Allow Download", isOn: $viewModel.allowDownload)
            Divider().padding(.leading, 44)
            toggleRow("Allow Remixes", isOn: $viewModel.allowRemix)
            Divider().padding(.leading, 44)
            toggleRow("Allow Commercial Use", isOn: $viewModel.allowCommercialUse)
        }
    }

    // MARK: - Monetization Section

    private var monetizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monetization")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            toggleRow("Available for Purchase", isOn: $viewModel.requiresPurchase)
            if viewModel.requiresPurchase {
                TextField("Price (USD)", text: $viewModel.price)
                    .font(.system(size: 15))
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.leading, 44)
            }

            toggleRow("Available for Lease", isOn: $viewModel.allowLease)
            if viewModel.allowLease {
                TextField("Lease Price (USD)", text: $viewModel.leasePrice)
                    .font(.system(size: 15))
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.leading, 44)
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(PrivacySetting.allCases, id: \.self) { option in
                    Button {
                        viewModel.privacySetting = option
                    } label: {
                        Text(option.label)
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                viewModel.privacySetting == option
                                    ? Color.brand
                                    : Color(.secondarySystemGroupedBackground)
                            )
                            .foregroundStyle(
                                viewModel.privacySetting == option ? .white : .secondary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Upload Button

    @ViewBuilder
    private var uploadButton: some View {
        // Error
        if case .error(let message) = viewModel.uploadState {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        Button {
            Task { await viewModel.upload() }
        } label: {
            HStack(spacing: 10) {
                if viewModel.uploadState == .uploading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                }
                Text(
                    viewModel.uploadState == .uploading
                        ? "Uploading..." : "Publish \(headerTitle)"
                )
                .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                viewModel.canUpload && viewModel.uploadState != .uploading
                    ? Color.brand : Color(.systemGray3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!viewModel.canUpload || viewModel.uploadState == .uploading)
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 20)
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func mediaChip(
        _ label: String, icon: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Color.brand : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(selected ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    nonisolated private func fileAttachmentContent(
        icon: String, name: String?, placeholder: String, attached: Bool
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(attached ? Color.green.opacity(0.12) : Color.brand.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: attached ? "checkmark" : icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(attached ? .green : Color.brand)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? placeholder)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(attached ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if attached {
                    Text("Tap to change")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.graySecondary)
                }
            }

            Spacer()

            if !attached {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.brand)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func fileAttachmentRow(
        icon: String, name: String?, placeholder: String, attached: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            fileAttachmentContent(icon: icon, name: name, placeholder: placeholder, attached: attached)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 15))
        }
        .tint(Color.brand)
        .padding(.vertical, 6)
    }
}
