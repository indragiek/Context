// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import SwiftUI

struct ToolDetailWrapper: View {
  let tool: Tool
  let store: StoreOf<ToolsFeature>
  @Dependency(\.toolCache) var toolCache
  @State private var toolState = ToolState()

  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      ToolDetailView(
        tool: tool,
        toolState: $toolState,
        server: viewStore.server,
        onStateUpdate: { newState in
          toolState = newState
          viewStore.send(.updateToolState(toolName: tool.name, toolState: newState))
        }
      )
      .task {
        // Load cached state whenever the view appears
        toolState = await toolCache.get(for: tool.name) ?? ToolState()
      }
      .onChange(of: tool.name) { _, newToolName in
        // When tool changes, load the new tool's cached state
        Task { @MainActor in
          toolState = await toolCache.get(for: newToolName) ?? ToolState()
        }
      }
    }
  }
}
