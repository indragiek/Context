// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI

struct DetailView: View {
  let store: StoreOf<AppFeature>

  var body: some View {
    WithViewStore(
      self.store,
      observe: { state in
        state.sidebarFeature.selectedServerID.flatMap { state.servers[id: $0] }
      }
    ) { viewStore in
      if let selectedServer = viewStore.state {
        tabContent(for: selectedServer)
      } else {
        noServerSelectedView
      }
    }
  }

  @ViewBuilder
  private func tabContent(for selectedServer: ServerFeature.State) -> some View {
    switch selectedServer.selectedTab {
    case .logs:
      logsTabContent(selectedServer)
    case .tools:
      toolsTabContent(selectedServer)
    case .prompts:
      promptsTabContent(selectedServer)
    case .resources:
      resourcesTabContent(selectedServer)
    }
  }

  @ViewBuilder
  private func logsTabContent(_ selectedServer: ServerFeature.State) -> some View {
    if let selectedLogID = selectedServer.logsFeature.selectedLogIDs.first,
      let selectedCachedLogEntry = selectedServer.logsFeature.cachedLogs.first(where: {
        $0.id == selectedLogID
      }
      )
    {
      JSONValueView(jsonValue: selectedCachedLogEntry.logEntry.params.data)
    } else {
      ContentUnavailableView(
        "No Log Selected",
        systemImage: "doc.text",
        description: Text("Select a log entry to view details")
      )
    }
  }

  @ViewBuilder
  private func toolsTabContent(_ selectedServer: ServerFeature.State) -> some View {
    IfLetStore(
      store.scope(
        state: \.serverLifecycleFeature.servers[id: selectedServer.id],
        action: \.serverLifecycleFeature.serverFeature[id: selectedServer.id]
      )
    ) { serverStore in
      if let selectedToolName = selectedServer.toolsFeature.selectedToolName,
        let selectedTool = selectedServer.toolsFeature.tools.first(where: {
          $0.name == selectedToolName
        })
      {
        ToolDetailWrapper(
          tool: selectedTool,
          store: serverStore.scope(state: \.toolsFeature, action: \.toolsFeature)
        )
      } else {
        ContentUnavailableView(
          "No Tool Selected",
          systemImage: "wrench.and.screwdriver",
          description: Text("Select a tool to view details")
        )
      }
    }
  }

  @ViewBuilder
  private func promptsTabContent(_ selectedServer: ServerFeature.State) -> some View {
    IfLetStore(
      store.scope(
        state: \.serverLifecycleFeature.servers[id: selectedServer.id],
        action: \.serverLifecycleFeature.serverFeature[id: selectedServer.id]
      )
    ) { serverStore in
      if let selectedPromptName = selectedServer.promptsFeature.selectedPromptName,
        let selectedPrompt = selectedServer.promptsFeature.prompts.first(where: {
          $0.name == selectedPromptName
        })
      {
        PromptDetailWrapper(
          prompt: selectedPrompt,
          store: serverStore.scope(state: \.promptsFeature, action: \.promptsFeature)
        )
      } else {
        ContentUnavailableView(
          "No Prompt Selected",
          systemImage: "text.bubble",
          description: Text("Select a prompt to view details")
        )
      }
    }
  }

  @ViewBuilder
  private func resourcesTabContent(_ selectedServer: ServerFeature.State) -> some View {
    if let selectedResourceID = selectedServer.resourcesFeature.selectedResourceID,
      let selectedResource = selectedServer.resourcesFeature.resources.first(where: {
        $0.id == selectedResourceID
      })
    {
      ResourceDetailView(resource: selectedResource, server: selectedServer.server)
    } else if let selectedTemplateID = selectedServer.resourcesFeature.selectedResourceTemplateID,
      let selectedTemplate = selectedServer.resourcesFeature.resourceTemplates.first(where: {
        $0.id == selectedTemplateID
      })
    {
      ResourceTemplateDetailView(template: selectedTemplate, server: selectedServer.server)
    } else {
      ContentUnavailableView(
        "No Resource Selected",
        systemImage: "folder",
        description: Text("Select a resource or template to view details")
      )
    }
  }

  private var noServerSelectedView: some View {
    ContentUnavailableView(
      "No Server Selected",
      systemImage: "sidebar.right",
      description: Text("Select a server from the sidebar")
    )
  }
}

#Preview {
  DetailView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
