//
//  FolderContentsScreen.swift
//  Volspire
//
//

import DesignSystem
import Services
import SwiftUI
import UniformTypeIdentifiers

struct FolderContentsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FolderContentsViewModel

    init(folderId: String, folderName: String) {
        _viewModel = State(
            wrappedValue: FolderContentsViewModel(folderId: folderId, folderName: folderName)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Text(viewModel.folderName)
                        .font(.system(size: 26, weight: .semibold))
                    Spacer()

                    Button {
                        viewModel.showFilePicker = true
                    } label: {
                        Group {
                            if viewModel.isUploading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.primary)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isUploading)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 8)
                .padding(.bottom, 16)

                switch viewModel.loadingState {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                case .error(let message):
                    ContentUnavailableView(
                        "Something went wrong",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                case .loaded where viewModel.files.isEmpty:
                    ContentUnavailableView(
                        "No Files",
                        systemImage: "doc",
                        description: Text("This folder is empty")
                    )
                case .loaded:
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.files) { file in
                            fileRow(file)
                            if file.id != viewModel.files.last?.id {
                                Divider()
                                    .padding(.leading, 60)
                                    .padding(.horizontal, ViewConst.screenPaddings)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .gradientBackground()
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.audio, .image, .movie, .pdf, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.uploadFile(url: url)
                    }
                }
            case .failure(let error):
                print("[FolderContents] File picker error: \(error)")
            }
        }
        .alert("Upload Failed", isPresented: .init(
            get: { viewModel.uploadError != nil },
            set: { if !$0 { viewModel.uploadError = nil } }
        )) {
            Button("OK") { viewModel.uploadError = nil }
        } message: {
            Text(viewModel.uploadError ?? "")
        }
        .task {
            await viewModel.loadFiles()
        }
    }
}

// MARK: - Subviews

private extension FolderContentsScreen {

    func fileRow(_ file: ApiFolderFile) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.iconColor(for: file).opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: viewModel.icon(for: file))
                    .font(.system(size: 18))
                    .foregroundStyle(viewModel.iconColor(for: file))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 15))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let size = viewModel.formattedSize(for: file) {
                        Text(size)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if let duration = viewModel.formattedDuration(for: file) {
                        Text(duration)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.relativeTime(from: file.createdAt))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteFile(file)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    FolderContentsScreen(folderId: "test", folderName: "My Beats")
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
