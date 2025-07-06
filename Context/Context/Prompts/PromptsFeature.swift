// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import GRDB
import SharingGRDB

struct PromptState: Sendable {
  var argumentValues: [String: String] = [:]
  var messages: [PromptMessage] = []
  var hasLoadedOnce = false
  var rawResponseJSON: JSONValue?
  var rawResponseError: String?
}

extension PromptState: Equatable {
  static func == (lhs: PromptState, rhs: PromptState) -> Bool {
    lhs.argumentValues == rhs.argumentValues && lhs.hasLoadedOnce == rhs.hasLoadedOnce
      && lhs.rawResponseError == rhs.rawResponseError
  }
}

@Reducer
struct PromptsFeature {
  @ObservableState
  struct State: Equatable {
    let server: MCPServer
    var prompts: [Prompt] = []
    var selectedPromptName: String?
    var lastSelectedPromptName: String?  // Preserved across reconnects
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

    var filteredPrompts: [Prompt] {
      guard !searchQuery.isEmpty else { return prompts }

      let query = searchQuery.lowercased()
      return prompts.filter { prompt in
        // Match on name
        if prompt.name.lowercased().contains(query) {
          return true
        }

        // Match on description
        if let description = prompt.description,
          description.lowercased().contains(query)
        {
          return true
        }

        // Match on argument names
        if let arguments = prompt.arguments {
          for argument in arguments {
            if argument.name.lowercased().contains(query) {
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
    case promptsLoaded([Prompt])
    case loadingFailed(any Error)
    case promptSelected(String?)
    case searchQueryChanged(String)
    case updatePromptState(promptName: String, promptState: PromptState)
    case clearState
    case connectionStateChanged(Client.ConnectionState)
    case reconnect
    case prepareForReconnection
    case loadMorePrompts
    case morePromptsLoaded(prompts: [Prompt], nextCursor: String?)
    case loadMorePromptsFailed(any Error)
    case loadIfNeeded
  }

  @Dependency(\.promptCache) var promptCache
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

            let (prompts, nextCursor) = try await client.listPrompts()
            await send(.promptsLoaded(prompts))
            await send(.morePromptsLoaded(prompts: [], nextCursor: nextCursor))
          } catch {
            await send(.loadingFailed(error))
          }
        }

      case let .promptsLoaded(prompts):
        state.isLoading = false
        state.prompts = prompts
        state.hasLoadedOnce = true
        state.error = nil

        if let lastSelected = state.lastSelectedPromptName,
          prompts.contains(where: { $0.name == lastSelected })
        {
          state.selectedPromptName = lastSelected
        } else if let selectedPromptName = state.selectedPromptName,
          !prompts.contains(where: { $0.name == selectedPromptName })
        {
          state.selectedPromptName = nil
        }

        if state.selectedPromptName == nil {
          state.selectedPromptName = state.filteredPrompts.first?.name ?? prompts.first?.name
        }

        return .none

      case let .loadingFailed(error):
        state.isLoading = false
        state.error = NotConnectedError(underlyingError: error)
        state.hasRequestedInitialLoad = false  // Reset to allow retry
        return .none

      case let .promptSelected(name):
        state.selectedPromptName = name
        state.lastSelectedPromptName = name
        return .none

      case let .searchQueryChanged(query):
        state.searchQuery = query

        if let selectedPromptName = state.selectedPromptName,
          !state.filteredPrompts.contains(where: { $0.name == selectedPromptName })
        {
          state.selectedPromptName = state.filteredPrompts.first?.name
        }

        return .none

      case let .updatePromptState(promptName, promptState):
        return .run { _ in
          await promptCache.set(promptState, for: promptName)
        }

      case .clearState:
        state.lastSelectedPromptName = state.selectedPromptName ?? state.lastSelectedPromptName
        state.prompts = []
        state.selectedPromptName = nil
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
          state.selectedPromptName = nil
        }
        return .none

      case .reconnect:
        return .none

      case .prepareForReconnection:
        state.isLoading = true
        state.error = nil
        state.hasRequestedInitialLoad = false
        return .none

      case .loadMorePrompts:
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
              await send(.loadMorePromptsFailed(NotConnectedError()))
              return
            }

            let (prompts, nextCursor) = try await client.listPrompts(cursor: cursor)
            await send(.morePromptsLoaded(prompts: prompts, nextCursor: nextCursor))
          } catch {
            await send(.loadMorePromptsFailed(error))
          }
        }

      case let .morePromptsLoaded(prompts, nextCursor):
        state.isLoadingMore = false
        state.prompts.append(contentsOf: prompts)
        state.nextCursor = nextCursor
        state.hasMore = nextCursor != nil
        return .none

      case .loadMorePromptsFailed:
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
