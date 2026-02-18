//
//  RootTabView.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import SwiftUI

struct RootTabView: View {
    @State private var showNewPost = false
    @State private var selectedTab: TabBarItem = .home

    init() {
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        let tabTopColor = isDark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.92, alpha: 1)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = tabTopColor
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = tabTopColor
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(TabBarItem.allCases, id: \.self) { item in
                Tab(value: item, role: item.role) {
                    NavigationStack {
                        item.destinationView
                    }
                } label: {
                    Label {
                        Text(item.title)
                    } icon: {
                        item.image
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .accentColor(.brand)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .newPost {
                selectedTab = oldValue
                showNewPost = true
            }
        }
        .sheet(isPresented: $showNewPost) {
            NewPostView()
        }
    }
}

private extension TabBarItem {
    @MainActor
    @ViewBuilder
    var destinationView: some View {
        switch self {
        case .home:
            HomeScreen()
                .withRouter()
        case .library:
            LibraryScreen()
                .withRouter()
        case .newPost:
            EmptyView()
        case .search:
            SearchScreen()
                .withRouter()
        case .profile:
            ProfileScreen()
                .withRouter()
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    RootTabView()
        .environment(playerController)
        .environment(dependencies)
}
