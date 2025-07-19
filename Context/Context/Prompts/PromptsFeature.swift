// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Foundation
import GRDB
import SharingGRDB

enum PromptLoadingState: Sendable, Equatable {
  case idle
  case loading
  case loaded
  case failed
}

struct PromptCompletionState: Sendable, Equatable {
  var argumentCompletions: [String: [String]] = [:]
  var loadingCompletions: [String: Bool] = [:]
  var hasSelectedCompletion: [String: Bool] = [:]
}

struct PromptState: Sendable {
  var argumentValues: [String: String] = [:]
  var messages: [PromptMessage] = []
  var hasLoadedOnce = false
  var responseJSON: JSONValue?
  var responseError: (any Error)?
  var loadingState: PromptLoadingState = .idle
  var rawResponse: GetPromptResponse.Result?
  var viewMode: PromptViewMode = .preview
}

extension PromptState: Equatable {
  static func == (lhs: PromptState, rhs: PromptState) -> Bool {
    // Compare properties that are Equatable
    guard
      lhs.argumentValues == rhs.argumentValues && lhs.hasLoadedOnce == rhs.hasLoadedOnce
        && lhs.loadingState == rhs.loadingState && lhs.viewMode == rhs.viewMode
        && lhs.responseJSON == rhs.responseJSON
    else {
      return false
    }

    // Compare errors by their existence and type
    let lhsErrorType = lhs.responseError.map { type(of: $0) }
    let rhsErrorType = rhs.responseError.map { type(of: $0) }
    let lhsErrorMessage = lhs.responseError?.localizedDescription
    let rhsErrorMessage = rhs.responseError?.localizedDescription

    guard lhsErrorType == rhsErrorType && lhsErrorMessage == rhsErrorMessage else {
      return false
    }

    // For non-Equatable types, compare counts as a proxy
    // This isn't perfect but better than always returning false
    return lhs.messages.count == rhs.messages.count
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

    // Completion state (not cached)
    var promptCompletions: [String: PromptCompletionState] = [:]

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
    case fetchCompletions(promptName: String, argumentName: String, argumentValue: String)
    case completionsLoaded(promptName: String, argumentName: String, completions: [String])
    case completionsFailed(promptName: String, argumentName: String)
    case argumentFocusChanged(promptName: String, argumentName: String?, value: String)
    case argumentValueChanged(
      promptName: String, argumentName: String, oldValue: String, newValue: String)
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

      case let .fetchCompletions(promptName, argumentName, argumentValue):
        // Check if server supports completions
        return .run { [server = state.server] send in
          guard let client = await mcpClientManager.existingClient(for: server),
            await client.serverCapabilities?.completions != nil
          else {
            return
          }

          do {
            let reference = Reference.prompt(name: promptName)
            let (values, _, _) = try await client.complete(
              ref: reference,
              argumentName: argumentName,
              argumentValue: argumentValue
            )
            await send(
              .completionsLoaded(
                promptName: promptName, argumentName: argumentName, completions: values))
          } catch {
            await send(.completionsFailed(promptName: promptName, argumentName: argumentName))
          }
        }

      case let .completionsLoaded(promptName, argumentName, completions):
        var completionState = state.promptCompletions[promptName] ?? PromptCompletionState()
        completionState.argumentCompletions[argumentName] = completions
        completionState.loadingCompletions[argumentName] = false
        state.promptCompletions[promptName] = completionState
        return .none

      case let .completionsFailed(promptName, argumentName):
        var completionState = state.promptCompletions[promptName] ?? PromptCompletionState()
        completionState.argumentCompletions[argumentName] = []
        completionState.loadingCompletions[argumentName] = false
        state.promptCompletions[promptName] = completionState
        return .none

      case let .argumentFocusChanged(promptName, argumentName, value):
        if let argumentName = argumentName {
          // Field is focused - fetch completions
          var completionState = state.promptCompletions[promptName] ?? PromptCompletionState()
          completionState.hasSelectedCompletion[argumentName] = false
          completionState.loadingCompletions[argumentName] = true
          state.promptCompletions[promptName] = completionState
          return .send(
            .fetchCompletions(
              promptName: promptName, argumentName: argumentName, argumentValue: value))
        } else {
          // Field lost focus - clear completions
          if var completionState = state.promptCompletions[promptName] {
            for arg in completionState.argumentCompletions.keys {
              completionState.argumentCompletions[arg] = []
              completionState.hasSelectedCompletion[arg] = false
            }
            state.promptCompletions[promptName] = completionState
          }
          return .none
        }

      case let .argumentValueChanged(promptName, argumentName, oldValue, newValue):
        // Only fetch completions if the user actually typed
        if oldValue != newValue {
          var completionState = state.promptCompletions[promptName] ?? PromptCompletionState()
          completionState.hasSelectedCompletion[argumentName] = false

          // Check if new value matches a completion
          if let completions = completionState.argumentCompletions[argumentName],
            completions.contains(newValue)
          {
            completionState.hasSelectedCompletion[argumentName] = true
          }

          state.promptCompletions[promptName] = completionState

          // Fetch new completions
          return .send(
            .fetchCompletions(
              promptName: promptName, argumentName: argumentName, argumentValue: newValue))
        }
        return .none
      }
    }
  }
}
