//
//  UploadTrackScreen.swift
//  Volspire
//
//  Track upload form, mirroring the web's track-create page: cover + title
//  + genre up top, then public preview, collaborators, tags, buyer
//  downloads, tier monetization, collaboration flag, and privacy — with the
//  pinned Publish CTA and always-visible validation at the bottom.
//

import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct UploadTrackScreen: View {
    @State var viewModel: UploadTrackViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAudioPicker = false
    @State private var showCoverPicker = false
    @State private var showVideoPicker = false
    @State private var showGenrePicker = false
    @State private var showAssetPicker = false
    @State private var pickingAssetKind: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedVideo: PhotosPickerItem?
    @FocusState private var priceFieldFocused: Bool

    private let tagSuggestions = [
        "808", "trap", "melodic", "dark", "drill", "r&b", "lo-fi",
        "chill", "hype", "afro", "soulful", "vocal", "instrumental",
    ]

    private var isUploading: Bool {
        viewModel.uploadState == .uploading
    }

    private var assetPickerTypes: [UTType] {
        switch pickingAssetKind {
        case "mp3": [.mp3]
        case "wav": [.wav]
        default: [.zip]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    coverAndTitleRow
                    descriptionField
                    publicPreviewSection
                    collaboratorsSection
                    tagsSection
                    // Buyer downloads only feed the paid tiers — hidden while
                    // monetization is gated off (matches the web).
                    if FeatureFlags.marketplace {
                        buyerDownloadsSection
                    }
                    distributionSection
                    collaborationSection
                    privacySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        .gradientBackground()
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedPhoto, matching: .images)
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedVideo, matching: .videos)
        .sheet(isPresented: $showGenrePicker) {
            GenrePickerSheet(genre: $viewModel.genre)
        }
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
        .fileImporter(
            isPresented: $showAssetPicker,
            allowedContentTypes: assetPickerTypes,
            allowsMultipleSelection: false
        ) { result in
            guard let kind = pickingAssetKind else { return }
            pickingAssetKind = nil
            if case .success(let urls) = result, let url = urls.first {
                viewModel.handleAssetFile(kind: kind, result: .success(url))
            } else if case .failure(let error) = result {
                viewModel.handleAssetFile(kind: kind, result: .failure(error))
            }
        }
        .onChange(of: selectedVideo) { _, newValue in
            guard let newValue else { return }
            // Loading a large camera-roll video out of Photos has no progress
            // signal of its own — flip this on right away so the drop zone
            // doesn't just sit there looking frozen while it loads.
            viewModel.isProcessingVideo = true
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    let fileName = "video_\(UUID().uuidString).mov"
                    viewModel.handleVideoData(data, fileName: fileName)
                } else {
                    viewModel.isProcessingVideo = false
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
        UploadFlowHeader(title: "Upload Track") { dismiss() }
    }

    // MARK: - Bottom bar (pinned CTA + always-visible status)

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if case .error(let message) = viewModel.uploadState {
                statusRow(message, color: UploadTheme.errorText)
            } else if let hint = viewModel.validationHint {
                statusRow(hint, color: Color.vText3)
            }

            Button {
                Task { await viewModel.upload() }
            } label: {
                HStack(spacing: 10) {
                    if isUploading {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(isUploading ? "Uploading…" : "Publish Track")
                        .font(.appHeadline)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canUpload || isUploading)
            .opacity(viewModel.canUpload && !isUploading ? 1 : 0.3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Color.vBase
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.vBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        }
    }

    private func statusRow(_ message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LucideIcon(.triangleAlert, .sm)
                .foregroundStyle(color)
            Text(message)
                .font(.appFootnote)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cover + title + genre

    private var coverAndTitleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                showCoverPicker = true
            } label: {
                coverBox
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "",
                    text: $viewModel.title,
                    prompt: Text("Track title").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .uploadFieldShell()
                .onChange(of: viewModel.title) { _, newValue in
                    if newValue.count > 100 {
                        viewModel.title = String(newValue.prefix(100))
                    }
                }

                Button {
                    showGenrePicker = true
                } label: {
                    HStack {
                        Text(viewModel.genre.isEmpty ? "Genre" : viewModel.genre)
                            .font(.appBody)
                            .foregroundStyle(viewModel.genre.isEmpty ? Color.vText3 : .white)
                        Spacer()
                        LucideIcon(.chevronDown, .sm)
                            .foregroundStyle(Color.vText3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .uploadFieldShell()
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var coverBox: some View {
        ZStack {
            if let img = viewModel.coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                UploadTheme.fieldFill
                VStack(spacing: 6) {
                    LucideIcon(.image, .lg)
                        .foregroundStyle(Color.vText3)
                    Text("Cover art")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if viewModel.coverImage == nil {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
        }
    }

    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField(
                "",
                text: $viewModel.description,
                prompt: Text("What's the story behind this track?").foregroundStyle(Color.vText3),
                axis: .vertical
            )
            .font(.appBody)
            .foregroundStyle(.white)
            .lineLimit(3...6)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .uploadFieldShell()
            .onChange(of: viewModel.description) { _, newValue in
                if newValue.count > 500 {
                    viewModel.description = String(newValue.prefix(500))
                }
            }

            Text("\(viewModel.description.count)/500")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
        }
    }

    // MARK: - Public preview (the streamable file)

    private var publicPreviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Public Preview")

            Text(FeatureFlags.marketplace
                ? "What everyone hears when they press play. Free listeners can also download this file. Paid downloads go in Buyer Downloads."
                : "What everyone hears when they press play. Anyone can stream and download it for free.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            HStack(spacing: 8) {
                UploadPill("Audio", icon: .fileAudio, expands: true, selected: viewModel.mediaType == .audio) {
                    viewModel.mediaType = .audio
                }
                UploadPill("Video", icon: .video, expands: true, selected: viewModel.mediaType == .video) {
                    viewModel.mediaType = .video
                }
            }

            attachmentArea
        }
    }

    @ViewBuilder
    private var attachmentArea: some View {
        if viewModel.mediaType == .audio {
            if let data = viewModel.audioData {
                attachedFileCard(icon: .fileAudio, name: viewModel.audioFileName, bytes: data.count) {
                    viewModel.audioData = nil
                    viewModel.audioFileName = nil
                }
            } else {
                Button {
                    showAudioPicker = true
                } label: {
                    dropZone(
                        icon: .fileAudio,
                        title: "Tap to choose an audio file",
                        hint: "MP3, WAV, FLAC, AIFF"
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            if let data = viewModel.videoData {
                attachedFileCard(icon: .video, name: viewModel.videoFileName, bytes: data.count) {
                    viewModel.videoData = nil
                    viewModel.videoFileName = nil
                    viewModel.videoAudioOnly = false
                    selectedVideo = nil
                }
                videoModeToggle
            } else if viewModel.isProcessingVideo {
                videoProcessingCard
            } else {
                Button {
                    showVideoPicker = true
                } label: {
                    dropZone(
                        icon: .video,
                        title: "Tap to choose a video",
                        hint: "MP4, MOV from your library"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Shown from the moment a video is picked until it's loaded + compressed
    /// — replaces the empty drop zone so it never looks frozen mid-pick.
    private var videoProcessingCard: some View {
        VStack(spacing: 14) {
            iconBox(.video)
            VStack(spacing: 8) {
                Text(viewModel.videoProcessingProgress > 0 ? "Compressing video…" : "Loading video…")
                    .font(.appCallout)
                    .foregroundStyle(Color.vText2)
                ProgressView(value: viewModel.videoProcessingProgress)
                    .tint(.white)
                    .frame(maxWidth: 160)
                if viewModel.videoProcessingProgress > 0 {
                    Text("\(Int(viewModel.videoProcessingProgress * 100))%")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
        )
    }

    /// Choice shown under an attached video: keep the video, or upload only its
    /// extracted audio (as an audio track).
    private var videoModeToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                UploadPill("Keep video", icon: .video, expands: true, selected: !viewModel.videoAudioOnly) {
                    viewModel.videoAudioOnly = false
                }
                UploadPill("Audio only", icon: .fileAudio, expands: true, selected: viewModel.videoAudioOnly) {
                    viewModel.videoAudioOnly = true
                }
            }
            Text(viewModel.videoAudioOnly
                ? "Only the audio from this video is uploaded — it'll play as an audio track."
                : "The full video uploads and plays with picture.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
        }
    }

    private func dropZone(icon: LucideIcon.Name, title: String, hint: String) -> some View {
        VStack(spacing: 14) {
            iconBox(icon)

            VStack(spacing: 4) {
                Text(title)
                    .font(.appCallout)
                    .foregroundStyle(Color.vText2)
                Text(hint)
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
        )
        .contentShape(.rect)
    }

    private func attachedFileCard(
        icon: LucideIcon.Name, name: String?, bytes: Int, clear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            iconBox(icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? "File")
                    .font(.appBodyMedium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(UploadClipRows.formatBytes(bytes))
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
            }

            Spacer()

            Button(action: clear) {
                LucideIcon(.trash2, .md)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .uploadFieldShell(cornerRadius: 16)
    }

    private func iconBox(_ icon: LucideIcon.Name) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.vBorder, lineWidth: 1)
            LucideIcon(icon, .md)
                .foregroundStyle(Color.vText2)
        }
        .frame(width: 40, height: 40)
    }

    // MARK: - Collaborators (user search → credited list, role inline)

    private var collaboratorsSection: some View {
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
                    prompt: Text("Search username…").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
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

    private func avatarCircle(initial: String) -> some View {
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

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Tags")
            UploadTagInput(tags: $viewModel.tags, suggestions: tagSuggestions)
        }
    }

    // MARK: - Buyer downloads (per-tier assets, uploaded once)

    private var buyerDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Buyer Downloads")

            Text("Files paying buyers get after they purchase. Upload each format once — the paid tiers below decide who gets what.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)
            Text("All optional. Skip if you only enable Free / Stream.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)

            assetRow(
                kind: "mp3",
                label: "MP3",
                hint: "Lossy audio. Included with Creator and Exclusive.",
                fileName: viewModel.mp3FileName,
                bytes: viewModel.mp3Data?.count
            )
            assetRow(
                kind: "wav",
                label: "WAV",
                hint: "Lossless, production-grade. Included with Creator, Pro, and Exclusive.",
                fileName: viewModel.wavFileName,
                bytes: viewModel.wavData?.count
            )
            assetRow(
                kind: "stems",
                label: "Stems (zip)",
                hint: "Multitrack zip for remixing. Included with Pro and Exclusive.",
                fileName: viewModel.stemsFileName,
                bytes: viewModel.stemsData?.count
            )
        }
    }

    private func assetRow(
        kind: String, label: String, hint: String, fileName: String?, bytes: Int?
    ) -> some View {
        let attached = bytes != nil
        return Button {
            guard !attached else { return }
            pickingAssetKind = kind
            showAssetPicker = true
        } label: {
            HStack(spacing: 12) {
                iconBox(.fileAudio)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(label)
                            .font(.appBodyMedium)
                            .foregroundStyle(attached ? .white : Color.vText2)
                        if !attached {
                            Text("· optional")
                                .font(.appFootnote)
                                .foregroundStyle(Color.vText3)
                        }
                    }
                    if let fileName, let bytes {
                        Text("\(fileName) · \(UploadClipRows.formatBytes(bytes))")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(hint)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                if attached {
                    Button {
                        viewModel.clearAsset(kind: kind)
                    } label: {
                        LucideIcon(.trash2, .sm)
                            .foregroundStyle(Color.vText3)
                            .frame(width: 40, height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    LucideIcon(.upload, .sm)
                        .foregroundStyle(Color.vText3)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(attached ? UploadTheme.fieldFill : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        UploadTheme.border,
                        style: attached ? StrokeStyle(lineWidth: 1) : UploadTheme.dashed
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Distribution & Monetization (tiers)

    private var distributionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider(FeatureFlags.marketplace ? "Distribution & Monetization" : "Distribution")

            Text(FeatureFlags.marketplace
                ? "Free stream and download are always on. Toggle paid tiers to sell format-specific bundles on top."
                : "Every track is free to stream and download.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            // Only the free tier while monetization is gated off (matches the web).
            ForEach(FeatureFlags.marketplace ? Array(TrackTier.allCases) : [.free], id: \.self) { tier in
                tierCard(tier)
            }

            if let tierValidation = viewModel.tierValidation {
                HStack(spacing: 8) {
                    LucideIcon(.triangleAlert, .xs)
                    Text(tierValidation)
                        .font(.appFootnote)
                }
                .foregroundStyle(UploadTheme.warningText)
            }
        }
    }

    private func tierCard(_ tier: TrackTier) -> some View {
        let enabled = viewModel.tierEnabled[tier] == true
        let isFree = tier == .free
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                guard !isFree else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.setTier(tier, enabled: !enabled)
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.label)
                            .font(.appBodyMedium)
                            .foregroundStyle(enabled ? .white : Color.vText2)
                        Text(tier.blurb)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    UploadSwitch(isOn: enabled)
                        .opacity(isFree ? 0.3 : 1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isFree)

            if enabled, !isFree {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.appBody)
                        .foregroundStyle(Color.vText3)
                    TextField(
                        "",
                        text: Binding(
                            get: { viewModel.tierPrice[tier] ?? "" },
                            set: { viewModel.tierPrice[tier] = $0.filter { "0123456789.".contains($0) } }
                        ),
                        prompt: Text("0.00").foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .keyboardType(.decimalPad)
                    .focused($priceFieldFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                priceFieldFocused = false
                            }
                            .font(.appCallout)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .uploadFieldShell()

                let included = viewModel.includedAssets(for: tier)
                if included.isEmpty {
                    Text("Missing required files")
                        .font(.appFootnote)
                        .foregroundStyle(UploadTheme.warningText)
                } else {
                    ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(included, id: \.self) { kind in
                            Text(kind.uppercased())
                                .font(.appLabel)
                                .foregroundStyle(Color.vText2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                                .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(enabled ? UploadTheme.fieldFill : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(enabled ? Color.white.opacity(0.25) : Color.vBorder, lineWidth: 1)
        )
    }

    // MARK: - Collaboration flag

    private var collaborationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            UploadSectionDivider("Collaboration")

            UploadToggleRow(
                label: "Looking for collaborators on this track",
                hint: "Your track shows in the Looking for Collab feed. Other artists can DM you to offer.",
                isOn: $viewModel.lookingForCollab
            )
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Privacy & Release")

            HStack(spacing: 8) {
                UploadPill("Public", icon: .globe, expands: true, selected: viewModel.visibility == "public") {
                    viewModel.visibility = "public"
                }
                UploadPill("Private", icon: .lock, expands: true, selected: viewModel.visibility == "private") {
                    viewModel.visibility = "private"
                }
            }
        }
    }
}
