// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AsyncAlgorithms
import ComposableArchitecture
import ContextCore
import Foundation
import GRDB
import SharingGRDB

enum LogsError: LocalizedError {
  case streamError(String)

  var errorDescription: String? {
    switch self {
    case .streamError(let message):
      return message
    }
  }
}

@Reducer
struct LogsFeature {
  private static let maxLogCount = 1000

  @ObservableState
  struct State: Equatable {
    let server: MCPServer
    var cachedLogs: [CachedLogEntry] = []
    var selectedLogIDs: Set<LogEntry.ID> = []
    var searchQuery: String = ""
    var error: String? = nil
    var isLoading = false
    var hasLoadedOnce = false

    var filteredLogs: [CachedLogEntry] {
      if searchQuery.isEmpty {
        return cachedLogs
      }
      return cachedLogs.filter { cachedLog in
        cachedLog.contains(searchQuery: searchQuery)
      }
    }

    init(server: MCPServer) {
      self.server = server
    }
  }

  enum Action {
    case onAppear
    case onDisappear
    case onConnected
    case startedListening
    case loadingFailed(any Error)
    case logReceived(LoggingMessageNotification.Params)
    case logSelected(Set<LogEntry.ID>)
    case searchQueryChanged(String)
    case clearError
  }

  @Dependency(\.mcpClientManager) var mcpClientManager
  @Dependency(\.defaultDatabase) var database

  private enum CancelID {
    case logSubscription
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        return .none

      case .onDisappear:
        return .none

      case .onConnected:
        return .merge(
          .cancel(id: CancelID.logSubscription),
          .run { [server = state.server] send in
            guard let client = await mcpClientManager.existingClient(for: server) else {
              return
            }

            let connectionState = await client.currentConnectionState
            guard connectionState == .connected else {
              return
            }

            let logsStream = await client.logs
            await send(.startedListening)

            for await log in logsStream {
              if let level = log.level {
                await send(
                  .logReceived(
                    LoggingMessageNotification.Params(
                      level: level,
                      logger: log.logger,
                      data: log.data
                    )))
              }
            }
          }
          .cancellable(id: CancelID.logSubscription)
        )

      case .startedListening:
        state.isLoading = false
        state.hasLoadedOnce = true
        state.error = nil
        return .none

      case let .loadingFailed(error):
        state.isLoading = false
        state.error = error.localizedDescription
        return .none

      case let .logReceived(params):
        let newLog = LogEntry(params: params)
        state.cachedLogs.append(CachedLogEntry(newLog))

        if state.cachedLogs.count > Self.maxLogCount {
          let removeCount = state.cachedLogs.count - Self.maxLogCount
          state.cachedLogs.removeFirst(removeCount)

          let remainingIDs = Set(state.cachedLogs.map { $0.id })
          state.selectedLogIDs = state.selectedLogIDs.intersection(remainingIDs)
        }

        if state.cachedLogs.count == 1 && state.selectedLogIDs.isEmpty {
          state.selectedLogIDs = [newLog.id]
        }
        return .none

      case let .logSelected(ids):
        state.selectedLogIDs = ids
        return .none

      case let .searchQueryChanged(query):
        state.searchQuery = query

        let filteredIDs = Set(state.filteredLogs.map { $0.id })
        let validSelectedIDs = state.selectedLogIDs.intersection(filteredIDs)

        if validSelectedIDs.isEmpty && !state.filteredLogs.isEmpty {
          if !state.selectedLogIDs.isEmpty, let firstLog = state.filteredLogs.first {
            state.selectedLogIDs = [firstLog.id]
          } else {
            state.selectedLogIDs = []
          }
        } else {
          state.selectedLogIDs = validSelectedIDs
        }

        return .none

      case .clearError:
        state.error = nil
        return .none
      }
    }
  }
}
