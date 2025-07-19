// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import SwiftUI

struct PromptDetailWrapper: View {
  let prompt: Prompt
  let store: StoreOf<PromptsFeature>
  @Dependency(\.promptCache) var promptCache
  @State private var promptState: PromptState?
  @State private var isLoadingCache = true

  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      Group {
        if isLoadingCache {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          PromptDetailView(
            prompt: prompt,
            server: viewStore.server,
            promptState: promptState ?? PromptState(),
            onStateUpdate: { newState in
              viewStore.send(.updatePromptState(promptName: prompt.name, promptState: newState))
            },
            store: store
          )
          .id(prompt.name)  // Force view recreation when prompt changes
        }
      }
      .task(id: prompt.name) {
        isLoadingCache = true
        promptState = await promptCache.get(for: prompt.name)
        isLoadingCache = false
      }
    }
  }
}
