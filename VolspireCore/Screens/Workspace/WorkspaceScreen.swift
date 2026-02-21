//
//  WorkspaceScreen.swift
//  Volspire
//
//

import DesignSystem
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
                        // Notifications action
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

                // Quick Access
                quickAccessSection

                // View mode toggle + sort
                toolbar
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                // Files & Folders
                if viewMode == .grid {
                    gridContent
                        .padding(.horizontal, ViewConst.screenPaddings)
                } else {
                    listContent
                }
            }
            .padding(.bottom, 32)
        }
        .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
        .navigationBarHidden(true)
        .gradientBackground()
    }
}

// MARK: - View Mode

enum WorkspaceViewMode {
    case list, grid
}

// MARK: - Subviews

private extension WorkspaceScreen {

    // MARK: Quick Access
    var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.quickAccess) { item in
                        quickAccessCard(item)
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
            }
        }
    }

    func quickAccessCard(_ item: WorkspaceItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))

                Image(systemName: item.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(item.iconColor)
            }
            .frame(width: 120, height: 80)

            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Text(item.modifiedDate)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }

    // MARK: Toolbar
    var toolbar: some View {
        HStack {
            Text("My Files")
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
                    Button("Date modified") {}
                    Button("Size") {}
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
            ForEach(viewModel.files) { item in
                fileRow(item)
                if item.id != viewModel.files.last?.id {
                    Divider()
                        .padding(.leading, 60)
                        .padding(.horizontal, ViewConst.screenPaddings)
                }
            }
        }
    }

    func fileRow(_ item: WorkspaceItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: item.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(item.iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let size = item.size {
                        Text(size)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.modifiedDate)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                // More actions
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
            ForEach(viewModel.files) { item in
                fileGridCard(item)
            }
        }
    }

    func fileGridCard(_ item: WorkspaceItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(.systemGray6)

                Image(systemName: item.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(item.iconColor)
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(item.modifiedDate)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
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
