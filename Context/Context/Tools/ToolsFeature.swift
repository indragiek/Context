// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import GRDB
import SharingGRDB

@Reducer
struct ToolsFeature {
  @ObservableState
  struct State: Equatable {
    let server: MCPServer
    var tools: [Tool] = []
    var selectedToolName: String?
    var lastSelectedToolName: String?  // Preserved across reconnects
    var searchQuery = ""
    var isLoading = false
    var error: NotConnectedError?
    var hasLoadedOnce = false
    var hasRequestedInitialLoad = false

    // Pagination state
    var nextCursor: String?
    var isLoadingMore = false
    var hasMore = true  // Assume there might be more until proven otherwise

    init(server: MCPServer) {
      self.server = server
    }

    var filteredTools: [Tool] {
      guard !searchQuery.isEmpty else { return tools }

      let query = searchQuery.lowercased()
      return tools.filter { tool in
        // Match on name
        if tool.name.lowercased().contains(query) {
          return true
        }

        // Match on description
        if let description = tool.description,
          description.lowercased().contains(query)
        {
          return true
        }

        // Match on input schema property names
        if let properties = tool.inputSchema.properties {
          for (key, _) in properties {
            if key.lowercased().contains(query) {
              return true
            }
          }
        }

        return false
      }
    }
  }

  enum Action {
    case onAppear
    case onConnected
    case toolsLoaded([Tool])
    case loadingFailed(any Error)
    case toolSelected(String?)
    case searchQueryChanged(String)
    case updateToolState(toolName: String, toolState: ToolState)
    case clearState
    case connectionStateChanged(Client.ConnectionState)
    case reconnect
    case prepareForReconnection
    case loadMoreTools
    case moreToolsLoaded(tools: [Tool], nextCursor: String?)
    case loadMoreToolsFailed(any Error)
    case loadIfNeeded
  }

  @Dependency(\.toolCache) var toolCache
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

            let (tools, nextCursor) = try await client.listTools()
            await send(.toolsLoaded(tools))
            await send(.moreToolsLoaded(tools: [], nextCursor: nextCursor))
          } catch {
            await send(.loadingFailed(error))
          }
        }

      case let .toolsLoaded(tools):
        state.isLoading = false
        state.tools = tools
        state.hasLoadedOnce = true
        state.error = nil

        if let lastSelected = state.lastSelectedToolName,
          tools.contains(where: { $0.name == lastSelected })
        {
          state.selectedToolName = lastSelected
        } else if let selectedToolName = state.selectedToolName,
          !tools.contains(where: { $0.name == selectedToolName })
        {
          state.selectedToolName = nil
        }

        if state.selectedToolName == nil {
          state.selectedToolName = state.filteredTools.first?.name ?? tools.first?.name
        }

        return .none

      case let .loadingFailed(error):
        state.isLoading = false
        state.error = NotConnectedError(underlyingError: error)
        state.hasRequestedInitialLoad = false  // Reset to allow retry
        return .none

      case let .toolSelected(name):
        state.selectedToolName = name
        state.lastSelectedToolName = name
        return .none

      case let .searchQueryChanged(query):
        state.searchQuery = query

        if let selectedToolName = state.selectedToolName,
          !state.filteredTools.contains(where: { $0.name == selectedToolName })
        {
          state.selectedToolName = state.filteredTools.first?.name
        }

        return .none

      case let .updateToolState(toolName, toolState):
        return .run { _ in
          await toolCache.set(toolState, for: toolName)
        }

      case .clearState:
        state.lastSelectedToolName = state.selectedToolName ?? state.lastSelectedToolName
        state.tools = []
        state.selectedToolName = nil
        state.searchQuery = ""
        state.error = nil
        state.hasLoadedOnce = false
        state.hasRequestedInitialLoad = false

        // Reset pagination state
        state.nextCursor = nil
        state.isLoadingMore = false
        state.hasMore = true

        return .none

      case let .connectionStateChanged(connectionState):
        if connectionState == .disconnected && state.hasLoadedOnce {
          state.error = NotConnectedError()
          state.isLoading = false
          state.selectedToolName = nil
        }
        return .none

      case .reconnect:
        return .none

      case .prepareForReconnection:
        state.isLoading = true
        state.error = nil
        state.hasRequestedInitialLoad = false
        return .none

      case .loadMoreTools:
        guard !state.isLoadingMore,
          state.hasMore,
          let cursor = state.nextCursor
        else {
          return .none
        }

        state.isLoadingMore = true

        return .run { [server = state.server] send in
          do {
            guard let client = await mcpClientManager.existingClient(for: server) else {
              await send(.loadMoreToolsFailed(NotConnectedError()))
              return
            }

            let (tools, nextCursor) = try await client.listTools(cursor: cursor)
            await send(.moreToolsLoaded(tools: tools, nextCursor: nextCursor))
          } catch {
            await send(.loadMoreToolsFailed(error))
          }
        }

      case let .moreToolsLoaded(tools, nextCursor):
        state.isLoadingMore = false
        state.tools.append(contentsOf: tools)
        state.nextCursor = nextCursor
        state.hasMore = nextCursor != nil
        return .none

      case .loadMoreToolsFailed:
        state.isLoadingMore = false
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
