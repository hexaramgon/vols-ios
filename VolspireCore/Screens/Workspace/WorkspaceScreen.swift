//
//  WorkspaceScreen.swift
//  Volspire
//
//

import DesignSystem
import Services
import SwiftUI

struct WorkspaceScreen: View {
    @Environment(Router.self) var router
    @State private var viewModel = WorkspaceScreenViewModel()
    @State private var viewMode: WorkspaceViewMode = .list

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    Text("Workspace")
                        .font(.system(size: 26, weight: .semibold))
                    Spacer()
                    Button {
                        router.navigateToMessages()
                    } label: {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        router.navigateToNotifications()
                    } label: {
                        Image(systemName: "bell")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 8)
                .padding(.bottom, 12)

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
                case .loaded where viewModel.folders.isEmpty:
                    ContentUnavailableView(
                        "No Folders",
                        systemImage: "folder",
                        description: Text("Create a folder to get started")
                    )
                case .loaded:
                    toolbar
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                    if viewMode == .grid {
                        gridContent
                            .padding(.horizontal, ViewConst.screenPaddings)
                    } else {
                        listContent
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
        .navigationBarHidden(true)
        .gradientBackground()
        .overlay(alignment: .bottomTrailing) {
            Button {
                viewModel.showCreateFolder = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, ViewConst.screenPaddings)
            .padding(.bottom, 80)
        }
        .task {
            await viewModel.loadFolders()
        }
        .sheet(isPresented: $viewModel.showCreateFolder) {
            createFolderSheet
        }
        .sheet(item: $viewModel.editingFolder) { _ in
            editFolderSheet
        }
    }
}

// MARK: - View Mode

enum WorkspaceViewMode {
    case list, grid
}

// MARK: - Subviews

private extension WorkspaceScreen {

    // MARK: Toolbar
    var toolbar: some View {
        HStack {
            Text("My Folders")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            HStack(spacing: 16) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = viewMode == .list ? .grid : .list
                    }
                } label: {
                    Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Button("Name") {}
                    Button("Date created") {}
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: List Content
    var listContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.folders) { folder in
                folderRow(folder)
                    .onTapGesture {
                        router.navigateToFolder(folderId: folder.folderId, folderName: folder.name)
                    }
                if folder.id != viewModel.folders.last?.id {
                    Divider()
                        .padding(.leading, 60)
                        .padding(.horizontal, ViewConst.screenPaddings)
                }
            }
        }
    }

    func folderRow(_ folder: ApiUserFolder) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.iconColor(for: folder).opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: folder.role == "owner" ? "folder.fill" : "folder.fill.badge.person.crop")
                    .font(.system(size: 18))
                    .foregroundStyle(viewModel.iconColor(for: folder))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 15))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if folder.role != "owner" {
                        Text(folder.role.capitalized)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.relativeTime(from: folder.createdAt))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                viewModel.startEditing(folder)
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

    // MARK: Grid Content
    var gridContent: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(viewModel.folders) { folder in
                folderGridCard(folder)
                    .onTapGesture {
                        router.navigateToFolder(folderId: folder.folderId, folderName: folder.name)
                    }
            }
        }
    }

    func folderGridCard(_ folder: ApiUserFolder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(.systemGray6)

                Image(systemName: folder.role == "owner" ? "folder.fill" : "folder.fill.badge.person.crop")
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.iconColor(for: folder))
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(viewModel.relativeTime(from: folder.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
    }

    // MARK: Create Folder Sheet
    var createFolderSheet: some View {
        folderFormSheet(
            title: "New Folder",
            name: $viewModel.newFolderName,
            description: $viewModel.newFolderDescription,
            actionLabel: "Create Folder",
            actionIcon: "plus.circle.fill",
            isBusy: viewModel.isCreatingFolder,
            isValid: !viewModel.newFolderName.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { viewModel.showCreateFolder = false },
            onAction: { await viewModel.createFolder() }
        )
    }

    // MARK: Edit Folder Sheet
    var editFolderSheet: some View {
        folderFormSheet(
            title: "Edit Folder",
            name: $viewModel.editFolderName,
            description: $viewModel.editFolderDescription,
            actionLabel: "Save Changes",
            actionIcon: "checkmark.circle.fill",
            isBusy: viewModel.isEditingFolder,
            isValid: !viewModel.editFolderName.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { viewModel.editingFolder = nil },
            onAction: { await viewModel.editFolder() }
        )
    }

    private func folderFormSheet(
        title: String,
        name: Binding<String>,
        description: Binding<String>,
        actionLabel: String,
        actionIcon: String,
        isBusy: Bool,
        isValid: Bool,
        onCancel: @escaping () -> Void,
        onAction: @escaping () async -> Void
    ) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Circle())
                }

                Spacer()

                Text(title)
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)

            // Fields
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Folder name", text: name)
                        .font(.system(size: 16))
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Optional description...", text: description, axis: .vertical)
                        .font(.system(size: 16))
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer()

            // Action button
            Button {
                Task { await onAction() }
            } label: {
                HStack(spacing: 10) {
                    if isBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: actionIcon)
                            .font(.system(size: 18))
                    }
                    Text(isBusy ? "Working..." : actionLabel)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isValid && !isBusy ? Color.brand : Color(.systemGray3))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!isValid || isBusy)
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
        .gradientBackground()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    WorkspaceScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
