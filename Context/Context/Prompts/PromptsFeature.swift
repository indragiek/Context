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

    return lhs.messages == rhs.messages
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
    var completionTasks: [String: Task<Void, Never>] = [:]

    // Prompt message fetch tasks
    var promptFetchTasks: [String: Task<Void, Never>] = [:]

    // Prompt states - single source of truth
    var promptStates: [String: PromptState] = [:]

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

    func promptState(for name: String) -> PromptState {
      promptStates[name] ?? PromptState()
    }

    func allRequiredArgumentsFilled(for prompt: Prompt) -> Bool {
      guard prompt.arguments != nil else { return true }

      // Get the prompt state from dependencies within reducer context
      return true  // This will be accessed differently in the reducer
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
    case storeCompletionTask(promptName: String, argumentName: String, task: Task<Void, Never>)
    case clearCompletionState(promptName: String)
    case loadPromptState(promptName: String)
    case promptStateLoaded(promptName: String, state: PromptState?)
    case initializePromptArguments(prompt: Prompt)
    case fetchPromptMessages(prompt: Prompt)
    case promptMessagesFetched(
      promptName: String, result: GetPromptResponse.Result, fetchedMessages: [PromptMessage])
    case promptMessagesFetchFailed(promptName: String, error: any Error)
    case cancelPromptMessagesFetch(promptName: String)
    case storePromptFetchTask(promptName: String, task: Task<Void, Never>)
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
        // Cancel any ongoing fetch for the previously selected prompt
        if let previousPrompt = state.selectedPromptName,
          previousPrompt != name,
          let task = state.promptFetchTasks[previousPrompt]
        {
          task.cancel()
          state.promptFetchTasks[previousPrompt] = nil
        }

        state.selectedPromptName = name
        state.lastSelectedPromptName = name

        // Load the prompt state if we haven't already
        if let name = name, state.promptStates[name] == nil {
          return .send(.loadPromptState(promptName: name))
        }

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
        state.promptStates[promptName] = promptState
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

        // Clear completion state and cancel all tasks
        state.promptCompletions = [:]
        for task in state.completionTasks.values {
          task.cancel()
        }
        state.completionTasks = [:]

        // Cancel all prompt fetch tasks
        for task in state.promptFetchTasks.values {
          task.cancel()
        }
        state.promptFetchTasks = [:]

        // Clear prompt states
        state.promptStates = [:]

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
        // Cancel any existing completion request for this argument
        let taskKey = "\(promptName):\(argumentName)"
        if let existingTask = state.completionTasks[taskKey] {
          existingTask.cancel()
        }

        // Check if server supports completions
        return .run { [server = state.server] send in
          guard let client = await mcpClientManager.existingClient(for: server),
            await client.serverCapabilities?.completions != nil
          else {
            return
          }

          let task = Task {
            do {
              let reference = Reference.prompt(name: promptName)
              let (values, _, _) = try await client.complete(
                ref: reference,
                argumentName: argumentName,
                argumentValue: argumentValue
              )

              // Check if task was cancelled before sending results
              if !Task.isCancelled {
                await send(
                  .completionsLoaded(
                    promptName: promptName, argumentName: argumentName, completions: values))
              }
            } catch {
              // Only send failure if not cancelled
              if !Task.isCancelled {
                await send(.completionsFailed(promptName: promptName, argumentName: argumentName))
              }
            }
          }

          // Store task for potential cancellation
          await send(
            .storeCompletionTask(promptName: promptName, argumentName: argumentName, task: task))

          // Await task completion
          await task.value
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
        // Update the prompt state with the new value
        var promptState = state.promptStates[promptName] ?? PromptState()
        promptState.argumentValues[argumentName] = newValue
        state.promptStates[promptName] = promptState
        
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

          // Update cache and fetch completions
          return .run { [promptState] send in
            await promptCache.set(promptState, for: promptName)
            await send(.fetchCompletions(
              promptName: promptName, argumentName: argumentName, argumentValue: newValue))
          }
        }
        return .run { [promptState] _ in
          await promptCache.set(promptState, for: promptName)
        }

      case let .storeCompletionTask(promptName, argumentName, task):
        let taskKey = "\(promptName):\(argumentName)"
        state.completionTasks[taskKey] = task
        return .none

      case let .loadPromptState(promptName):
        return .run { send in
          let cachedState = await promptCache.get(for: promptName)
          await send(.promptStateLoaded(promptName: promptName, state: cachedState))
        }

      case let .promptStateLoaded(promptName, cachedState):
        if let cachedState = cachedState {
          state.promptStates[promptName] = cachedState
        }
        return .none

      case let .clearCompletionState(promptName):
        // Clear completion state for this prompt
        state.promptCompletions[promptName] = nil

        // Cancel all tasks for this prompt
        for (key, task) in state.completionTasks where key.hasPrefix("\(promptName):") {
          task.cancel()
          state.completionTasks[key] = nil
        }

        return .none

      case let .initializePromptArguments(prompt):
        var promptState = state.promptStates[prompt.name] ?? PromptState()

        if let arguments = prompt.arguments {
          for argument in arguments {
            if promptState.argumentValues[argument.name] == nil {
              promptState.argumentValues[argument.name] = ""
            }
          }
        }

        return .send(.updatePromptState(promptName: prompt.name, promptState: promptState))

      case let .fetchPromptMessages(prompt):
        // Cancel any existing fetch for this prompt
        if let existingTask = state.promptFetchTasks[prompt.name] {
          existingTask.cancel()
        }

        // Update loading state immediately
        var promptState = state.promptStates[prompt.name] ?? PromptState()
        promptState.loadingState = .loading
        state.promptStates[prompt.name] = promptState

        return .run { [server = state.server, argumentValues = promptState.argumentValues] send in
          let task = Task {
            do {
              let client = try await mcpClientManager.client(for: server)

              if Task.isCancelled { return }

              let (description, fetchedMessages) = try await client.getPrompt(
                name: prompt.name, arguments: argumentValues)

              if Task.isCancelled { return }

              let result = GetPromptResponse.Result(
                description: description, messages: fetchedMessages)

              await send(
                .promptMessagesFetched(
                  promptName: prompt.name, result: result, fetchedMessages: fetchedMessages))
            } catch {
              if !Task.isCancelled {
                await send(.promptMessagesFetchFailed(promptName: prompt.name, error: error))
              }
            }
          }

          await send(.storePromptFetchTask(promptName: prompt.name, task: task))
          await task.value
        }

      case let .promptMessagesFetched(promptName, result, fetchedMessages):
        var promptState = state.promptStates[promptName] ?? PromptState()

        promptState.rawResponse = result

        do {
          let jsonData = try JSONUtility.prettyData(from: result)
          promptState.responseJSON = try JSONDecoder().decode(JSONValue.self, from: jsonData)
          promptState.responseError = nil
        } catch {
          promptState.responseJSON = nil
          promptState.responseError = error
        }

        // Process messages
        let templateProcessor = TemplateProcessor(argumentValues: promptState.argumentValues)
        promptState.messages = fetchedMessages.map { message in
          PromptMessage(
            role: message.role,
            content: templateProcessor.process(message.content)
          )
        }

        promptState.loadingState = .loaded
        promptState.hasLoadedOnce = true

        return .send(.updatePromptState(promptName: promptName, promptState: promptState))

      case let .promptMessagesFetchFailed(promptName, error):
        var promptState = state.promptStates[promptName] ?? PromptState()

        promptState.messages = []
        promptState.rawResponse = nil
        promptState.responseJSON = nil
        promptState.responseError = error
        promptState.loadingState = .failed
        promptState.hasLoadedOnce = true

        return .send(.updatePromptState(promptName: promptName, promptState: promptState))

      case let .cancelPromptMessagesFetch(promptName):
        if let task = state.promptFetchTasks[promptName] {
          task.cancel()
          state.promptFetchTasks[promptName] = nil
        }
        return .none

      case let .storePromptFetchTask(promptName, task):
        state.promptFetchTasks[promptName] = task
        return .none
      }
    }
  }
}
