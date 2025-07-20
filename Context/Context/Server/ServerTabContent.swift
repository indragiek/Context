// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct ServerTabContent: View {
  let store: StoreOf<ServerFeature>
  let selectedTab: ServerTab

  var body: some View {
    Group {
      switch selectedTab {
      case .tools:
        ToolsView(store: store.scope(state: \.toolsFeature, action: \.toolsFeature))
      case .prompts:
        PromptsView(store: store.scope(state: \.promptsFeature, action: \.promptsFeature))
      case .resources:
        ResourcesView(store: store.scope(state: \.resourcesFeature, action: \.resourcesFeature))
      case .logs:
        LogsView(store: store.scope(state: \.logsFeature, action: \.logsFeature))
      }
    }
  }
}
