//
//  CreateReleaseScreen.swift
//  Volspire
//
//  New post → Release: bulk-upload several tracks as one grouped release.
//  Cover art + details are shared by every track; the tracks section takes
//  many audio files at once (titles prefilled from the file names, reorder,
//  remove). Publish creates the release, then uploads the tracks one by one
//  through the normal `createTrackV2` path and adds each to the release as it
//  lands — per-row status, and a failed row can be retried without redoing
//  the ones that made it. Everything goes through RPCs (via LibraryStore).
//

import DesignSystem
import Observation
import PhotosUI
import Services
import SharedUtilities
import SwiftUI
import UniformTypeIdentifiers

// MARK: - View model

@Observable @MainActor
final class CreateReleaseViewModel {
    struct Row: Identifiable, Equatable {
        enum Status: Equatable { case pending, uploading, done, failed(String) }
        let id = UUID()
        var title: String
        let fileName: String
        /// The picked file, copied to temp storage — held on disk, not in
        /// memory, until its upload (a release can be many big WAVs).
        let fileURL: URL
        var status: Status = .pending
        /// Set once the track exists: a retry then only re-runs the "add to
        /// release" step instead of uploading a duplicate track.
        var trackId: String?
    }

    var title = ""
    var description = ""
    var genre = ""
    var visibility = "public"
    var rows: [Row] = []
    /// Files that bounced on pick (unsupported / unreadable).
    var pickErrors: [String] = []
    private(set) var isPublishing = false
    private(set) var publishError: String?
    private(set) var finished = false

    private var cover = CoverDraft()
    var coverImage: UIImage? { cover.image }

    /// Set once the release exists, so a retry only re-runs the failed rows.
    private var releaseId: String?
    /// The rows' temp copies, deleted when this view model goes away
    /// (published or abandoned). Not tied to the view's disappear — the cover
    /// cropper's full-screen cover fires that mid-flow.
    private let staged = StagedFiles()

    static let titleLimit = InputLimits.releaseTitle

    private let service: SupabaseService
    private let auth: AuthManager
    weak var library: LibraryStore?

    init(service: SupabaseService, auth: AuthManager) {
        self.service = service
        self.auth = auth
    }

    /// Tracks are optional — a release can go up empty to announce it, and
    /// tracks get added later from its page. Genre only matters for tracks.
    var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && cover.data != nil
            && (rows.isEmpty || !genre.isEmpty)
            && rows.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var hint: String? {
        if cover.data == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a cover and title to publish"
        }
        if !rows.isEmpty, genre.isEmpty { return "Pick a genre for the tracks" }
        if rows.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every track needs a title"
        }
        return nil
    }

    /// "Publish" / "Retry failed" once some rows are in.
    var ctaTitle: String { releaseId == nil ? "Publish Release" : "Retry Failed Tracks" }

    func setCover(_ image: UIImage) { cover.set(image) }

    /// Stages each picked file to temp storage off the main thread, checking
    /// only its first bytes (the format sniff) — never loading it whole.
    func addFiles(_ urls: [URL]) {
        Task {
            for url in urls {
                let name = url.lastPathComponent
                do {
                    let staged = try await Task.detached(priority: .userInitiated) { () throws -> URL? in
                        guard let copy = try SecurityScopedFile.stage(url, maxBytes: StorageBucket.postUploads.maxUploadBytes)
                        else { return nil }
                        do {
                            try MediaSniffer.validate(Self.head(of: copy), fileName: name)
                        } catch {
                            try? FileManager.default.removeItem(at: copy)
                            throw error
                        }
                        return copy
                    }.value
                    guard let staged else { continue }
                    self.staged.add(staged)
                    rows.append(Row(
                        title: (name as NSString).deletingPathExtension.singleLined.capped(at: Self.titleLimit),
                        fileName: name,
                        fileURL: staged
                    ))
                } catch {
                    pickErrors.append("\(name): \(error.localizedDescription)")
                }
            }
        }
    }

    /// The first 4 MB — all `MediaSniffer` looks at.
    nonisolated private static func head(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
    }

    func remove(_ row: Row) {
        guard !isPublishing, row.status != .done else { return }
        staged.discard(row.fileURL)
        rows.removeAll { $0.id == row.id }
    }


    func move(from source: IndexSet, to destination: Int) {
        guard !isPublishing, releaseId == nil else { return }
        rows.move(fromOffsets: source, toOffset: destination)
    }

    func publish() async {
        await ExtraBackgroundTime.run("Release upload") { await performPublish() }
    }

    private func performPublish() async {
        guard canPublish, !isPublishing, let library, let userId = auth.currentUserId else { return }
        isPublishing = true
        publishError = nil
        defer { isPublishing = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if releaseId == nil {
            do {
                releaseId = try await library.createRelease(
                    title: trimmedTitle,
                    description: description,
                    visibility: visibility,
                    releaseDate: nil,
                    coverData: cover.data
                )
            } catch {
                debugLog("[CreateReleaseVM] create: \(error)")
                publishError = "Couldn't create the release. Please try again."
                return
            }
        }
        guard let releaseId else { return }

        // Every remaining track starts at once: each is one background upload
        // job that also adds the track to the release, so a publish cut off
        // by the app closing still finishes (on the next launch at worst).
        let pending = rows.indices.filter { rows[$0].status != .done }
        for index in pending { rows[index].status = .uploading }
        let genre = genre, visibility = visibility, service = service
        let coverData = cover.data, coverFileName = cover.fileName
        await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
            for index in pending {
                let row = rows[index]
                group.addTask {
                    do {
                        if let existing = row.trackId {
                            // Created on an earlier attempt — only the add failed.
                            try await service.addTracksToRelease(releaseId: releaseId, trackIds: [existing])
                            return (index, .success(existing))
                        }
                        let durationMs = await UploadTrackViewModel.readMediaDurationMs(fileURL: row.fileURL)
                        // Streamed from disk — never loaded into memory.
                        let trackId = try await service.createTrackV2(
                            userId: userId,
                            title: row.title.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: nil,
                            genre: genre,
                            visibility: visibility,
                            mediaFile: row.fileURL,
                            mediaFileName: row.fileName,
                            isVideo: false,
                            coverData: coverData,
                            coverFileName: coverFileName,
                            credits: [],
                            tags: [],
                            durationMs: durationMs,
                            paidTiers: [],
                            assets: [],
                            lookingForCollab: false,
                            addToRelease: releaseId
                        )
                        return (index, .success(trackId))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let trackId):
                    rows[index].trackId = trackId
                    rows[index].status = .done
                case .failure(let error):
                    debugLog("[CreateReleaseVM] track \(rows[index].fileName): \(error)")
                    // The track exists; a retry only re-runs the add.
                    if let notAdded = error as? SupabaseService.TrackNotAddedToRelease, !notAdded.trackId.isEmpty {
                        rows[index].trackId = notAdded.trackId
                    }
                    rows[index].status = .failed("Upload failed")
                }
            }
        }
        // Uploads land in any order — put the release in the picked order.
        if rows.allSatisfy({ $0.status == .done }) {
            let order = rows.compactMap(\.trackId)
            do { try await library.reorderRelease(releaseId: releaseId, trackIds: order) }
            catch { debugLog("[CreateReleaseVM] reorder: \(error)") }
        }
        await library.refreshMyReleases()

        if rows.allSatisfy({ $0.status == .done }) {
            finished = true
            NotificationCenter.default.post(name: .ownContentPosted, object: nil, userInfo: [
                "confirmationTitle": "Release posted",
                "confirmationSubtitle": trimmedTitle,
            ])
        } else {
            publishError = "Some tracks didn't upload. Retry them, or remove them and publish."
        }
    }
}

/// Owns temp files and deletes whatever's left when released.
private final class StagedFiles {
    private var urls: Set<URL> = []

    func add(_ url: URL) { urls.insert(url) }

    func discard(_ url: URL) {
        urls.remove(url)
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - Screen

struct CreateReleaseScreen: View {
    @State var viewModel: CreateReleaseViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var libraryStore

    @State private var showCoverPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverCropTarget: CropTarget?
    @State private var showGenrePicker = false
    @State private var showAudioPicker = false

    var body: some View {
        VStack(spacing: 0) {
            UploadFlowHeader(icon: .layers, title: "New Release", subtitle: "Upload several tracks as one release") {
                dismiss()
            }

            ScrollView(showsIndicators: false) {
                // The mobile composer (same as a track's): cover, then the
                // title + story on the page, then the picks, then the tracklist.
                VStack(alignment: .leading, spacing: 28) {
                    ComposerCoverHero(
                        image: viewModel.coverImage,
                        caption: "Used for the release and every track in it"
                    ) { showCoverPicker = true }
                    VStack(alignment: .leading, spacing: 10) {
                        ComposerTitleField(text: $viewModel.title, prompt: "Release title",
                                           limit: CreateReleaseViewModel.titleLimit)
                        ComposerStoryField(text: $viewModel.description,
                                           prompt: "What's this release about?", limit: InputLimits.releaseDescription)
                    }
                    detailRows
                    tracksSection
                    // Same as a track's step 3: the pills inline, with a hint.
                    VStack(alignment: .leading, spacing: 14) {
                        UploadSectionDivider("Privacy")
                        UploadVisibilityPicker(
                            visibility: $viewModel.visibility,
                            publicHint: "Public: on your profile and anywhere releases show.",
                            privateHint: "Private: only you can see it. You can make it public later."
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .tapToDismissKeyboard()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                UploadBottomBar(error: viewModel.publishError, hint: viewModel.hint) {
                    AuthCTA(
                        title: viewModel.ctaTitle,
                        isLoading: viewModel.isPublishing,
                        isDisabled: !viewModel.canPublish
                    ) { Task { await viewModel.publish() } }
                }
            }
        }
        .background(Color.vBase.ignoresSafeArea())
        .task { viewModel.library = libraryStore }
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedPhoto, matching: .images)
        .sheet(isPresented: $showGenrePicker) { GenrePickerSheet(genre: $viewModel.genre) }

        // Own isolated view (two importers / an importer next to a cover on
        // one view shadow each other — see UploadTrackScreen).
        .background {
            Color.clear.fileImporter(
                isPresented: $showAudioPicker,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { viewModel.addFiles(urls) }
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let newValue,
                   let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    coverCropTarget = CropTarget(image: image.normalizedUp())
                }
            }
        }
        .fullScreenCover(item: $coverCropTarget) { target in
            ImageCropperView(
                image: target.image,
                onCrop: { data in
                    if let cropped = UIImage(data: data) { viewModel.setCover(cropped) }
                    coverCropTarget = nil
                },
                onCancel: { coverCropTarget = nil }
            )
        }
        .onChange(of: viewModel.finished) { _, done in if done { dismiss() } }
        .interactiveDismissDisabled(viewModel.isPublishing)
    }

    // MARK: Sections

    /// Genre — only matters once there are tracks.
    private var detailRows: some View {
        ComposerRowGroup {
            ComposerRow(
                icon: .music2, title: "Genre",
                value: viewModel.genre.isEmpty ? (viewModel.rows.isEmpty ? "For the tracks" : "Required") : viewModel.genre,
                placeholder: viewModel.genre.isEmpty
            ) { showGenrePicker = true }
        }
    }

    /// The tracklist: numbered rows (title editable in place, status,
    /// reorder / remove) in one card, "Add tracks" as its last row.
    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerHeading(title: "Tracks", trailing: viewModel.rows.isEmpty ? nil : "\(viewModel.rows.count)")

            ComposerRowGroup {
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsDivider() }
                    trackRow(index: index, row: row)
                }
                if !viewModel.rows.isEmpty { SettingsDivider() }
                ComposerAddRow(
                    title: viewModel.rows.isEmpty ? "Add tracks" : "Add more tracks",
                    trailing: viewModel.rows.isEmpty ? "Optional" : nil
                ) { showAudioPicker = true }
                .disabled(viewModel.isPublishing)
            }

            if viewModel.rows.isEmpty {
                Text("Pick several audio files at once — or publish it empty and add tracks later.")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText2)
            }

            ForEach(viewModel.pickErrors, id: \.self) { message in
                Text(message).font(.appCaption).foregroundStyle(Color.vError)
            }
        }
    }

    private func trackRow(index: Int, row: CreateReleaseViewModel.Row) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.appCaption)
                .monospacedDigit()
                .foregroundStyle(Color.vText3)
                .frame(width: 18)

            TextField("", text: Binding(
                get: { viewModel.rows.first { $0.id == row.id }?.title ?? "" },
                set: { new in
                    if let i = viewModel.rows.firstIndex(where: { $0.id == row.id }) {
                        viewModel.rows[i].title = new.singleLined.capped(at: CreateReleaseViewModel.titleLimit)
                    }
                }
            ), prompt: Text("Track title").foregroundStyle(Color.vText3))
                .font(.appFont.fileTitle)
                .foregroundStyle(Color.vText)
                .disabled(viewModel.isPublishing || row.status == .done)

            statusAccessory(row)

            if row.status != .done && !viewModel.isPublishing {
                HStack(spacing: 0) {
                    if index > 0 {
                        rowIcon(.chevronDown, "Move up", rotation: 180) { viewModel.move(from: [index], to: index - 1) }
                    }
                    rowIcon(.x, "Remove") { viewModel.remove(row) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // A failed row tints, the rest sit flat in the card.
        .background({ if case .failed = row.status { Color.vErrorFill } else { Color.clear } }())
    }

    @ViewBuilder
    private func statusAccessory(_ row: CreateReleaseViewModel.Row) -> some View {
        switch row.status {
        case .pending: EmptyView()
        case .uploading: ProgressView().tint(Color.vText2).controlSize(.small)
        case .done: LucideIcon(.check, .sm).foregroundStyle(Color.vSuccessText)
        case .failed(let message): Text(message).font(.appCaption).foregroundStyle(Color.vError).lineLimit(1)
        }
    }

    private func rowIcon(_ icon: LucideIcon.Name, _ label: String, rotation: Double = 0,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, .md)
                .rotationEffect(.degrees(rotation))
                .foregroundStyle(Color.vText3)
                .frame(width: 30, height: 30)
                .minimumHitArea(for: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
