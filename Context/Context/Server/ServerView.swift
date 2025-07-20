// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI

struct ServerView: View {
  let store: StoreOf<ServerFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(spacing: 0) {
        if !viewStore.connectionErrors.isEmpty {
          ConnectionErrorBanner(
            errors: viewStore.connectionErrors,
            onDismiss: { viewStore.send(.clearErrors) }
          )
        }

        ServerTabContent(store: store, selectedTab: viewStore.selectedTab)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationTitle(viewStore.server.name)
      .navigationSubtitle(connectionStateText(for: viewStore.connectionState))
      .toolbar {
        ToolbarItem(placement: .principal) {
          ServerTabSwitcher(
            selectedTab: viewStore.selectedTab,
            onTabSelected: { tab in
              viewStore.send(.tabSelected(tab))
            }
          )
        }

        #if DEBUG
          ToolbarItem(placement: .automatic) {
            Button("Load Mock Errors") {
              viewStore.send(.loadMockErrors)
            }
          }
        #endif
      }
      .onAppear {
        viewStore.send(.onAppear)
      }
      .onDisappear {
        viewStore.send(.onDisappear)
      }
      .sheet(
        store: self.store.scope(
          state: \.$authenticationState,
          action: \.authenticationFeature
        )
      ) { store in
        AuthenticationView(store: store)
      }
    }
  }

  private func connectionStateText(for state: Client.ConnectionState) -> String {
    switch state {
    case .connecting: "Connecting"
    case .connected: "Connected"
    case .disconnected: "Disconnected"
    case .disconnecting: "Disconnecting"
    }
  }
}

#Preview {
  NavigationStack {
    ServerView(
      store: Store(
        initialState: ServerFeature.State(
          server: MCPServer(
            id: UUID(),
            name: "example-server",
            transport: .stdio,
            command: "/usr/bin/example",
            args: [],
            environment: nil,
            headers: nil
          ))
      ) {
        ServerFeature()
      }
    )
  }
}
