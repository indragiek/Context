// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import GRDB
import SharingGRDB

@Reducer
struct ResourcesFeature {
  enum ResourceSegment: String, CaseIterable {
    case resources = "Resources"
    case templates = "Templates"
  }

  @ObservableState
  struct State: Equatable {
    let server: MCPServer
    var resources: [Resource] = []
    var resourceTemplates: [ResourceTemplate] = []
    var selectedResourceID: String?
    var selectedResourceTemplateID: String?
    var lastSelectedResourceID: String?  // Preserved across reconnects
    var lastSelectedTemplateID: String?  // Preserved across reconnects
    var lastSelectedSegment: ResourceSegment = .resources  // Preserved across reconnects
    var searchQuery: String = ""
    var isLoading = false
    var error: NotConnectedError?
    var hasLoadedOnce = false
    var hasRequestedInitialLoad = false
    var selectedSegment: ResourceSegment = .resources

    // Pagination state
    var resourcesNextCursor: String?
    var templatesNextCursor: String?
    var isLoadingMoreResources = false
    var isLoadingMoreTemplates = false
    var hasMoreResources = true  // Assume there might be more until proven otherwise
    var hasMoreTemplates = true  // Assume there might be more until proven otherwise

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
    case segmentChanged(ResourceSegment)
    case clearState
    case connectionStateChanged(Client.ConnectionState)
    case reconnect
    case prepareForReconnection
    case loadMoreResources
    case moreResourcesLoaded(resources: [Resource], nextCursor: String?)
    case loadMoreResourcesFailed(any Error)
    case loadMoreTemplates
    case moreTemplatesLoaded(templates: [ResourceTemplate], nextCursor: String?)
    case loadMoreTemplatesFailed(any Error)
    case loadIfNeeded
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

            let (resources, resourcesNextCursor) = try await client.listResources()
            let (templates, templatesNextCursor) = try await client.listResourceTemplates()
            await send(.resourcesLoaded(resources: resources, templates: templates))

            // Store pagination cursors
            await send(.moreResourcesLoaded(resources: [], nextCursor: resourcesNextCursor))
            await send(.moreTemplatesLoaded(templates: [], nextCursor: templatesNextCursor))
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

        // Restore segment selection
        state.selectedSegment = state.lastSelectedSegment

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
        state.hasRequestedInitialLoad = false  // Reset to allow retry
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

        // Note: We don't reset pagination state when searching.
        // The filtered results will show items from all loaded pages.
        // This provides a better UX as users can search across all loaded data.

        // Only update selection for the currently selected segment
        if state.selectedSegment == .resources {
          if let selectedResourceID = state.selectedResourceID {
            if !state.filteredResources.contains(where: { $0.id == selectedResourceID }) {
              state.selectedResourceID = nil
              if let firstResource = state.filteredResources.first {
                state.selectedResourceID = firstResource.id
              }
            }
          } else if state.selectedResourceID == nil && !state.filteredResources.isEmpty {
            // If no selection and we have filtered results, select the first one
            state.selectedResourceID = state.filteredResources.first?.id
          }
        } else {
          // Templates segment
          if let selectedTemplateID = state.selectedResourceTemplateID {
            if !state.filteredResourceTemplates.contains(where: { $0.id == selectedTemplateID }) {
              state.selectedResourceTemplateID = nil
              if let firstTemplate = state.filteredResourceTemplates.first {
                state.selectedResourceTemplateID = firstTemplate.id
              }
            }
          } else if state.selectedResourceTemplateID == nil
            && !state.filteredResourceTemplates.isEmpty
          {
            // If no selection and we have filtered results, select the first one
            state.selectedResourceTemplateID = state.filteredResourceTemplates.first?.id
          }
        }

        return .none

      case let .segmentChanged(segment):
        state.selectedSegment = segment
        state.lastSelectedSegment = segment
        // Clear search when switching segments for better UX
        state.searchQuery = ""
        return .none

      case .clearState:
        if state.selectedResourceID != nil {
          state.lastSelectedResourceID = state.selectedResourceID
        }
        if state.selectedResourceTemplateID != nil {
          state.lastSelectedTemplateID = state.selectedResourceTemplateID
        }
        state.lastSelectedSegment = state.selectedSegment

        state.resources = []
        state.resourceTemplates = []
        state.selectedResourceID = nil
        state.selectedResourceTemplateID = nil
        state.searchQuery = ""
        state.error = nil
        state.hasLoadedOnce = false
        state.hasRequestedInitialLoad = false

        // Reset pagination state
        state.resourcesNextCursor = nil
        state.templatesNextCursor = nil
        state.isLoadingMoreResources = false
        state.isLoadingMoreTemplates = false
        state.hasMoreResources = true
        state.hasMoreTemplates = true

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
        state.hasRequestedInitialLoad = false
        return .none

      case .loadMoreResources:
        guard !state.isLoadingMoreResources,
          state.hasMoreResources,
          let cursor = state.resourcesNextCursor
        else {
          return .none
        }

        state.isLoadingMoreResources = true

        return .run { [server = state.server] send in
          do {
            guard let client = await mcpClientManager.existingClient(for: server) else {
              await send(.loadMoreResourcesFailed(NotConnectedError()))
              return
            }

            let (resources, nextCursor) = try await client.listResources(cursor: cursor)
            await send(.moreResourcesLoaded(resources: resources, nextCursor: nextCursor))
          } catch {
            await send(.loadMoreResourcesFailed(error))
          }
        }

      case let .moreResourcesLoaded(resources, nextCursor):
        state.isLoadingMoreResources = false
        state.resources.append(contentsOf: resources)
        state.resourcesNextCursor = nextCursor
        state.hasMoreResources = nextCursor != nil
        return .none

      case .loadMoreResourcesFailed:
        state.isLoadingMoreResources = false
        // Consider showing an error to the user for pagination failures
        return .none

      case .loadMoreTemplates:
        guard !state.isLoadingMoreTemplates,
          state.hasMoreTemplates,
          let cursor = state.templatesNextCursor
        else {
          return .none
        }

        state.isLoadingMoreTemplates = true

        return .run { [server = state.server] send in
          do {
            guard let client = await mcpClientManager.existingClient(for: server) else {
              await send(.loadMoreTemplatesFailed(NotConnectedError()))
              return
            }

            let (templates, nextCursor) = try await client.listResourceTemplates(cursor: cursor)
            await send(.moreTemplatesLoaded(templates: templates, nextCursor: nextCursor))
          } catch {
            await send(.loadMoreTemplatesFailed(error))
          }
        }

      case let .moreTemplatesLoaded(templates, nextCursor):
        state.isLoadingMoreTemplates = false
        state.resourceTemplates.append(contentsOf: templates)
        state.templatesNextCursor = nextCursor
        state.hasMoreTemplates = nextCursor != nil
        return .none

      case .loadMoreTemplatesFailed:
        state.isLoadingMoreTemplates = false
        // Consider showing an error to the user for pagination failures
        return .none

      case .loadIfNeeded:
        // Only load if we haven't loaded yet and haven't already requested a load
        guard !state.hasLoadedOnce && !state.hasRequestedInitialLoad else {
          return .none
        }

        state.hasRequestedInitialLoad = true
        state.isLoading = true
        state.error = nil

        return .send(.onConnected)
      }
    }
  }
}
