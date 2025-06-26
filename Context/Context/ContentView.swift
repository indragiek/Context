// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct ContentView: View {
  let store: StoreOf<AppFeature>

  var body: some View {
    WithViewStore(self.store, observe: \.sidebarFeature.selectedSidebarItem) { viewStore in
      Group {
        switch viewStore.state {
        case .chat:
          ChatView(store: store.scope(state: \.chatFeature, action: \.chatFeature))

        case .server(let serverID):
          IfLetStore(
            store.scope(
              state: \.serverLifecycleFeature.servers[id: serverID],
              action: \.serverLifecycleFeature.serverFeature[id: serverID]
            )
          ) { serverStore in
            ServerView(store: serverStore)
          } else: {
            ContentUnavailableView("Server Not Found", systemImage: "server.rack")
          }

        case .none:
          ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
        }
      }
    }
  }
}

#Preview {
  ContentView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
