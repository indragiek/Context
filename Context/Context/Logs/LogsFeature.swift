// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AsyncAlgorithms
import ComposableArchitecture
import ContextCore
import Foundation
import GRDB
import SharingGRDB

#if !SENTRY_DISABLED
import Sentry
#endif

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
            #if !SENTRY_DISABLED
            let transaction = SentrySDK.startTransaction(
              name: "logs.stream",
              operation: "task",
              bindToScope: true
            )
            transaction.setData(value: server.id.uuidString, key: "server_id")
            transaction.setData(value: "info", key: "log_level") // minimum log level
            transaction.setData(value: true, key: "stream_active")
            #endif
            
            guard let client = await mcpClientManager.existingClient(for: server) else {
              #if !SENTRY_DISABLED
              transaction.finish(status: .notFound)
              #endif
              return
            }

            let connectionState = await client.currentConnectionState
            guard connectionState == .connected else {
              #if !SENTRY_DISABLED
              transaction.finish(status: .unavailable)
              #endif
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
            
            #if !SENTRY_DISABLED
            transaction.finish()
            #endif
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
        #if !SENTRY_DISABLED
        let span = SentrySDK.span?.startChild(operation: "logs.process_entry") ?? SentrySDK.startTransaction(
          name: "logs.process_entry",
          operation: "task"
        )
        span.setData(value: params.level.rawValue, key: "log_level")
        span.setData(value: params.logger ?? "unknown", key: "log_source")
        span.setData(value: state.cachedLogs.count, key: "buffer_size")
        #endif
        
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
        
        #if !SENTRY_DISABLED
        // Check if this log matches current search query
        let matchesFilter = state.filteredLogs.contains { $0.id == newLog.id }
        span.setData(value: matchesFilter, key: "is_filtered")
        span.finish()
        #endif
        
        return .none

      case let .logSelected(ids):
        state.selectedLogIDs = ids
        return .none

      case let .searchQueryChanged(query):
        #if !SENTRY_DISABLED
        let span = SentrySDK.span?.startChild(operation: "logs.search") ?? SentrySDK.startTransaction(
          name: "logs.search",
          operation: "task"
        )
        span.setData(value: query.count, key: "query_length")
        span.setData(value: state.cachedLogs.count, key: "total_logs")
        #endif
        
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

        #if !SENTRY_DISABLED
        span.setData(value: state.filteredLogs.count, key: "filtered_count")
        span.finish()
        #endif

        return .none

      case .clearError:
        state.error = nil
        return .none
      }
    }
  }
}
