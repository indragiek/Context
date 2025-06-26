// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI

struct RootContentView: View {
  @Bindable var store: StoreOf<AppFeature>
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      SidebarView(store: store)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)
    } content: {
      ContentView(store: store)
        .frame(minWidth: 300, idealWidth: 450)
    } detail: {
      DetailView(store: store)
        .frame(minWidth: 400, idealWidth: 600)
    }
    #if !SENTRY_DISABLED
      .onReceive(NotificationCenter.default.publisher(for: .giveFeedback)) { _ in
        openWindow(id: "feedback")
      }
    #endif
    .sheet(
      isPresented: Binding(
        get: { store.withState(\.welcome.isVisible) },
        set: { _ in store.send(.welcome(.dismiss)) }
      )
    ) {
      WelcomeView(store: store.scope(state: \.welcome, action: \.welcome))
    }
    .alert(
      $store.scope(state: \.referenceServersAlert, action: \.referenceServersAlert)
    )
    .task {
      store.send(.onAppear)
    }
  }
}

#Preview {
  RootContentView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
