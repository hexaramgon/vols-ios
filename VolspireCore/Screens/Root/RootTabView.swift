//
//  RootTabView.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import SwiftUI

@Observable
class ConversationState {
    var activeConversation: String?

    func open(name: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            activeConversation = name
        }
    }

    func close() {
        withAnimation(.easeInOut(duration: 0.3)) {
            activeConversation = nil
        }
    }
}

struct RootTabView: View {
    @State private var showNewPost = false
    @State private var selectedTab: TabBarItem = .home
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingBack = false
    @Environment(ConversationState.self) var conversationState

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
        ZStack {
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
            .ignoresSafeArea(.keyboard)

            if let name = conversationState.activeConversation {
                ConversationScreen(contactName: name, onBack: {
                    conversationState.close()
                })
                .offset(x: dragOffset)
                .transition(.move(edge: .trailing))
                .zIndex(1)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onChanged { value in
                            let horizontal = value.translation.width
                            let vertical = abs(value.translation.height)
                            
                            if !isDraggingBack {
                                // Only activate if clearly horizontal and rightward
                                if horizontal > 50 && horizontal > vertical * 1.5 {
                                    isDraggingBack = true
                                }
                            }
                            
                            if isDraggingBack && horizontal > 0 {
                                dragOffset = horizontal
                            }
                        }
                        .onEnded { value in
                            if isDraggingBack && (value.translation.width > 120 || value.predictedEndTranslation.width > 250) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    dragOffset = UIScreen.main.bounds.width
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    dragOffset = 0
                                    isDraggingBack = false
                                    conversationState.activeConversation = nil
                                }
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dragOffset = 0
                                }
                                isDraggingBack = false
                            }
                        }
                )
            }
        }
        .environment(conversationState)
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
        case .workspace:
            WorkspaceScreen()
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
