//
//  AppView.swift
//  Volspire
//
//

import SwiftUI

struct AppView: View {
    @Environment(Dependencies.self) var dependencies
    var body: some View {
        OverlaidRootView()
            .environment(dependencies.playerController)
            .environment(\.managedObjectContext, dependencies.dataController.container.viewContext)
    }
}
