// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Foundation
import os

@Reducer
struct ServerLifecycleFeature {
  let logger: Logger

  init(
    logger: Logger = Logger(subsystem: "com.indragie.Context", category: "ServerLifecycleFeature")
  ) {
    self.logger = logger
  }

  @ObservableState
  struct State: Equatable {
    @Shared var servers: IdentifiedArrayOf<ServerFeature.State>

    init(servers: Shared<IdentifiedArrayOf<ServerFeature.State>>) {
      self._servers = servers
    }
  }

  enum Action {
    case reloadServerConnection(UUID)
    case disconnectServer(UUID)
    case serverFeature(IdentifiedActionOf<ServerFeature>)
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .reloadServerConnection(serverId):
        logger.info("Reloading server connection")
        var serverExists = false
        state.$servers.withLock { servers in
          if servers[id: serverId] != nil {
            serverExists = true
          }
        }
        return serverExists
          ? .send(.serverFeature(.element(id: serverId, action: .reloadConnection))) : .none

      case let .disconnectServer(serverId):
        return .send(.serverFeature(.element(id: serverId, action: .disconnect)))

      case .serverFeature:
        return .none
      }
    }
    .forEach(\.servers, action: \.serverFeature) { [logger] in
      ServerFeature(logger: logger)
    }
  }
}
