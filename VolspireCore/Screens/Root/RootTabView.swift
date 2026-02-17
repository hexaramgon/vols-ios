//
//  RootTabView.swift
//  Volspire
//
//

import Foundation
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ForEach(TabBarItem.allCases, id: \.self) { item in
                Tab(role: item.role) {
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
        case .search:
            SearchScreen()
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
