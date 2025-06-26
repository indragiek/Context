// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import GRDB
import SharingGRDB

@Reducer
struct ResourcesFeature {
  @ObservableState
  struct State: Equatable {
    let server: MCPServer
    var resources: [Resource] = []
    var resourceTemplates: [ResourceTemplate] = []
    var selectedResourceID: String?
    var selectedResourceTemplateID: String?
    var lastSelectedResourceID: String?  // Preserved across reconnects
    var lastSelectedTemplateID: String?  // Preserved across reconnects
    var searchQuery: String = ""
    var isLoading = true
    var error: NotConnectedError?
    var hasLoadedOnce = false

    var filteredResources: [Resource] {
      if searchQuery.isEmpty {
        return resources
      }
      let query = searchQuery.lowercased()
      return resources.filter { resource in
        resource.uri.lowercased().contains(query)
          || (resource.name?.lowercased().contains(query) ?? false)
          || (resource.description?.lowercased().contains(query) ?? false)
      }
    }

    var filteredResourceTemplates: [ResourceTemplate] {
      if searchQuery.isEmpty {
        return resourceTemplates
      }
      let query = searchQuery.lowercased()
      return resourceTemplates.filter { template in
        template.uriTemplate.lowercased().contains(query)
          || template.name.lowercased().contains(query)
          || (template.description?.lowercased().contains(query) ?? false)
      }
    }

    init(server: MCPServer) {
      self.server = server
    }
  }

  enum Action {
    case onAppear
    case onConnected
    case resourcesLoaded(resources: [Resource], templates: [ResourceTemplate])
    case loadingFailed(any Error)
    case resourceSelected(String?)
    case resourceTemplateSelected(String?)
    case searchQueryChanged(String)
    case clearState
    case connectionStateChanged(Client.ConnectionState)
    case reconnect
    case prepareForReconnection
  }

  @Dependency(\.mcpClientManager) var mcpClientManager
  @Dependency(\.defaultDatabase) var database

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        return .none

      case .onConnected:
        return .run { [server = state.server] send in
          do {
            guard let client = await mcpClientManager.existingClient(for: server) else {
              await send(.loadingFailed(NotConnectedError()))
              return
            }

            let (resources, _) = try await client.listResources()
            let (templates, _) = try await client.listResourceTemplates()
            await send(.resourcesLoaded(resources: resources, templates: templates))
          } catch {
            await send(.loadingFailed(error))
          }
        }

      case let .resourcesLoaded(resources, templates):
        state.isLoading = false
        state.resources = resources
        state.resourceTemplates = templates
        state.hasLoadedOnce = true
        state.error = nil

        var selectionRestored = false

        if let lastResourceID = state.lastSelectedResourceID,
          resources.contains(where: { $0.id == lastResourceID })
        {
          state.selectedResourceID = lastResourceID
          selectionRestored = true
        } else if let lastTemplateID = state.lastSelectedTemplateID,
          templates.contains(where: { $0.id == lastTemplateID })
        {
          state.selectedResourceTemplateID = lastTemplateID
          selectionRestored = true
        }

        if !selectionRestored {
          if let firstResource = resources.first {
            state.selectedResourceID = firstResource.id
          } else if let firstTemplate = templates.first {
            state.selectedResourceTemplateID = firstTemplate.id
          }
        }

        return .none

      case let .loadingFailed(error):
        state.isLoading = false
        state.error = NotConnectedError(underlyingError: error)
        return .none

      case let .resourceSelected(id):
        state.selectedResourceID = id
        state.selectedResourceTemplateID = nil
        state.lastSelectedResourceID = id
        state.lastSelectedTemplateID = nil
        return .none

      case let .resourceTemplateSelected(id):
        state.selectedResourceTemplateID = id
        state.selectedResourceID = nil
        state.lastSelectedTemplateID = id
        state.lastSelectedResourceID = nil
        return .none

      case let .searchQueryChanged(query):
        state.searchQuery = query

        if let selectedResourceID = state.selectedResourceID {
          if !state.filteredResources.contains(where: { $0.id == selectedResourceID }) {
            state.selectedResourceID = nil
            if let firstResource = state.filteredResources.first {
              state.selectedResourceID = firstResource.id
            }
          }
        }

        if let selectedTemplateID = state.selectedResourceTemplateID {
          if !state.filteredResourceTemplates.contains(where: { $0.id == selectedTemplateID }) {
            state.selectedResourceTemplateID = nil
            if state.selectedResourceID == nil,
              let firstTemplate = state.filteredResourceTemplates.first
            {
              state.selectedResourceTemplateID = firstTemplate.id
            }
          }
        }

        if state.selectedResourceID == nil && state.selectedResourceTemplateID == nil {
          if let firstResource = state.filteredResources.first {
            state.selectedResourceID = firstResource.id
          } else if let firstTemplate = state.filteredResourceTemplates.first {
            state.selectedResourceTemplateID = firstTemplate.id
          }
        }

        return .none

      case .clearState:
        if state.selectedResourceID != nil {
          state.lastSelectedResourceID = state.selectedResourceID
        }
        if state.selectedResourceTemplateID != nil {
          state.lastSelectedTemplateID = state.selectedResourceTemplateID
        }

        state.resources = []
        state.resourceTemplates = []
        state.selectedResourceID = nil
        state.selectedResourceTemplateID = nil
        state.searchQuery = ""
        state.error = nil
        state.hasLoadedOnce = false
        return .none

      case let .connectionStateChanged(connectionState):
        if connectionState == .disconnected && state.hasLoadedOnce {
          state.error = NotConnectedError()
          state.isLoading = false
          state.selectedResourceID = nil
          state.selectedResourceTemplateID = nil
        }
        return .none

      case .reconnect:
        return .none

      case .prepareForReconnection:
        state.isLoading = true
        state.error = nil
        return .none
      }
    }
  }
}
