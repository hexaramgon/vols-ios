//
//  ProfileScreen.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

enum ProfileSection: String, CaseIterable {
    case tracks = "Tracks"
    case services = "Services"
}

struct ProfileScreen: View {
    @Environment(Router.self) var router
    @Environment(Dependencies.self) var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileScreenViewModel()
    @State var scrollOffset: CGFloat = 0
    @State private var selectedSection: ProfileSection = .tracks
    @State private var showEditProfile = false
    @State private var showShareSheet = false

    let userId: String?

    init(userId: String? = nil) {
        self.userId = userId
    }

    /// Resolved user ID — uses auth user ID when none is provided (own profile tab)
    private var resolvedUserId: String {
        userId ?? dependencies.authManager.currentUserId ?? ""
    }

    var navBarOpacity: Double {
        let bannerHeight = UIScreen.size.width * 0.85
        let threshold = bannerHeight - 100
        if scrollOffset < threshold - 60 {
            return 0
        } else if scrollOffset >= threshold {
            return 1
        }
        return (scrollOffset - (threshold - 60)) / 60
    }

    private var isOwnProfile: Bool {
        userId == nil || userId == dependencies.authManager.currentUserId
    }

    var body: some View {
        Group {
            if viewModel.loadingState == .idle || viewModel.loadingState == .loading {
                ScrollView {
                    profileSkeletonContent
                }
                .scrollDisabled(true)
            } else {
                ScrollView {
                    scrollContent
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newValue in
                    scrollOffset = newValue
                }
            }
        }
        .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
        .ignoresSafeArea(edges: [.top])
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if !isOwnProfile {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            ZStack {
                Color(UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(white: 0.12, alpha: 1)
                        : UIColor(white: 0.92, alpha: 1)
                })
                .opacity(navBarOpacity)

                Text(viewModel.username)
                    .font(.system(size: 17, weight: .semibold))
                    .opacity(navBarOpacity)
                    .frame(maxWidth: .infinity)
                    .padding(.top, (UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows.first?.safeAreaInsets.top ?? 59))
            }
            .frame(height: (UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.safeAreaInsets.top ?? 59) + 44)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.2), value: navBarOpacity)
        }
        .enableSwipeBack()
        .sheet(isPresented: $showEditProfile) {
            EditProfileScreen(viewModel: viewModel)
        }
        .task {
            viewModel.mediaState = dependencies.mediaState
            viewModel.player = dependencies.mediaPlayer
            await viewModel.loadProfile(userId: resolvedUserId)
        }
    }

    var profileBarOpacity: Double {
        let imageHeight = UIScreen.size.width * 0.55
        let topOffset = imageHeight - scrollOffset - ProfileBar.Const.height
        let high: CGFloat = 140
        let low: CGFloat = 25

        if topOffset >= high {
            return 1
        } else if topOffset <= low {
            return 0
        }
        return (topOffset - low) / (high - low)
    }
}

private extension ProfileScreen {
    var scrollContent: some View {
        VStack(spacing: -ProfileBar.Const.height) {
            ParallaxHeaderView(height: UIScreen.size.width * 0.85) {
                if let bannerURL = viewModel.bannerImageURL {
                    KFImage(bannerURL)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                }
            }
            VStack(spacing: 0) {
                
                VStack(spacing: 0) {
                    // Avatar + name row, overlapping the banner
                    HStack(alignment: .center, spacing: 14) {
                        profileAvatar
                            .offset(y: -60)
                            .padding(.bottom, -60)
                        Text(viewModel.username.isEmpty ? "Profile" : viewModel.username)
                            .font(.system(size: 22, weight: .bold))
                        Spacer()
                    }
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 16) {
                        if !viewModel.bio.isEmpty {
                            Text(viewModel.bio)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }

                        if !viewModel.location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text(viewModel.location)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.top, 20)

                    profileInfo
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.top, 16)

                    actionButtons
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.top, 24)

                    sectionPicker
                        .padding(.top, 20)

                    TabView(selection: $selectedSection) {
                        Group {
                            if !viewModel.tracks.isEmpty {
                                tracksList
                            } else {
                                emptyPlaceholder(
                                    icon: "music.note",
                                    title: "No tracks yet",
                                    subtitle: "Tracks will appear here once uploaded"
                                )
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .tag(ProfileSection.tracks)

                        servicesContent
                            .frame(maxHeight: .infinity, alignment: .top)
                            .tag(ProfileSection.services)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(minHeight: 600)
                    .padding(.top, 12)

                    if viewModel.loadingState == .loading {
                        ProgressView()
                            .padding(.top, 40)
                    }

                    if case let .error(message) = viewModel.loadingState {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }

                    if isOwnProfile {
                        Button {
                            Task {
                                await dependencies.authManager.signOut()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 15))
                                Text("Sign Out")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.top, 32)
                    }
                }
                .gradientBackground()
            }
        }
    }

    var profileAvatar: some View {
        Group {
            if let profileImageURL = viewModel.profileImageURL {
                KFImage(profileImageURL)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color(.palette.textSecondary))
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
    }

    var profileInfo: some View {
        HStack {
            Spacer()
            statView(value: viewModel.trackCount, label: "Tracks")
            Spacer()
            statView(value: viewModel.followersCount, label: "Followers")
            Spacer()
            statView(value: viewModel.monthlyListenersCount, label: "Listeners")
            Spacer()
        }
    }

    var actionButtons: some View {
        HStack(spacing: 10) {
            if isOwnProfile {
                Button {
                    showEditProfile = true
                } label: {
                    Text("Edit Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.brand)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Button {
                    showShareSheet = true
                } label: {
                    Text("Share Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } else {
                Button {
                    // Follow action
                } label: {
                    Text("Follow")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.brand)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Button {
                    // Collab action
                } label: {
                    Text("Collab")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if isOwnProfile {
                Button {
                    router.navigateToSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } else {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            let profileLink = URL(string: "https://volspire.com/profile/\(resolvedUserId)")!
            ActivityViewController(activityItems: [profileLink])
                .presentationDetents([.medium, .large])
        }
    }

    func statView(value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProfileSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(section.rawValue)
                            .font(.system(size: 15, weight: selectedSection == section ? .semibold : .regular))
                            .foregroundStyle(selectedSection == section ? Color.primary.opacity(0.80) : .secondary)
                        Rectangle()
                            .fill(selectedSection == section ? Color.primary.opacity(0.80) : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    var servicesContent: some View {
        VStack(spacing: 12) {
            serviceCard(
                title: "Mixing & Mastering",
                description: "Professional mix and master for your track",
                type: "Audio",
                price: "$150"
            )
            serviceCard(
                title: "Beat Production",
                description: "Custom beat tailored to your style",
                type: "Production",
                price: "$200"
            )
            serviceCard(
                title: "Vocal Recording",
                description: "Studio-quality vocal recording session",
                type: "Recording",
                price: "$80"
            )
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 8)
    }

    func serviceCard(title: String, description: String, type: String, price: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(price)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.brand)
            }
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(type)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func emptyPlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Color(.systemGray3))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color(.systemGray2))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    var tracksList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // Latest Release
            if let latest = viewModel.latestRelease {
                Text("Latest Release")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.bottom, 12)

                latestReleaseCard(latest)
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.bottom, 24)
            }

            // Curated Tracks
            if !viewModel.curatedTracks.isEmpty {
                Text("Curated Tracks")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.bottom, 12)

                ForEach(viewModel.curatedTracks) { track in
                    trackRow(track)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    func latestReleaseCard(_ track: ProfileTrack) -> some View {
        HStack(spacing: 14) {
            if let coverURL = track.coverURL {
                KFImage(coverURL)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text("\(track.streams) streams")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    func trackRow(_ track: ProfileTrack) -> some View {
        HStack(spacing: 12) {
            if let coverURL = track.coverURL {
                KFImage(coverURL)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 48, height: 48)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 16))
                    .lineLimit(1)
                Text("\(track.streams) streams")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 8)
    }

    // MARK: - Skeleton Loading

    var profileSkeletonContent: some View {
        VStack(spacing: 0) {
            // Banner skeleton
            ShimmerView()
                .frame(height: UIScreen.size.width * 0.55)

            VStack(spacing: 0) {
                // Avatar + name row skeleton
                HStack(alignment: .center, spacing: 14) {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 90, height: 90)
                        .overlay(ShimmerView().clipShape(Circle()))
                        .offset(y: -60)
                        .padding(.bottom, -60)

                    ShimmerView()
                        .frame(width: 140, height: 20)
                        .clipShape(Capsule())

                    Spacer()
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 6)

                // Bio skeleton
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerView()
                        .frame(height: 14)
                        .clipShape(Capsule())
                    ShimmerView()
                        .frame(width: 200, height: 14)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 20)

                // Location skeleton
                HStack(spacing: 6) {
                    ShimmerView()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                    ShimmerView()
                        .frame(width: 120, height: 14)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 12)

                // Stats skeleton
                HStack(spacing: 24) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 4) {
                            ShimmerView()
                                .frame(width: 40, height: 18)
                                .clipShape(Capsule())
                            ShimmerView()
                                .frame(width: 60, height: 12)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 20)

                // Action buttons skeleton
                HStack(spacing: 12) {
                    ShimmerView()
                        .frame(height: 36)
                        .clipShape(Capsule())
                    ShimmerView()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 24)

                // Section picker skeleton
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { _ in
                        ShimmerView()
                            .frame(height: 32)
                            .clipShape(Capsule())
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 24)

                // Track list skeleton
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack(spacing: 12) {
                            ShimmerView()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 6) {
                                ShimmerView()
                                    .frame(width: 160, height: 14)
                                    .clipShape(Capsule())
                                ShimmerView()
                                    .frame(width: 80, height: 12)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.vertical, 10)
                    }
                }
                .padding(.top, 16)
            }
            .gradientBackground()
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Shimmer Effect

private struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        Color(.systemGray5)
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.3),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 300)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    ProfileScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
