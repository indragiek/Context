// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Cocoa
import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation
import GRDB
import SharingGRDB
import SwiftUI
import os

enum AppError: LocalizedError {
  case serverNotFound

  var errorDescription: String? {
    switch self {
    case .serverNotFound:
      return "Server not found in database"
    }
  }
}

@Reducer
struct AppFeature {
  private let logger: Logger

  init(logger: Logger = Logger(subsystem: "com.indragie.Context", category: "AppFeature")) {
    self.logger = logger
  }

  @Dependency(\.defaultDatabase) var database

  @ObservableState
  struct State: Equatable {
    var chatFeature = ChatFeature.State()
    var sidebarFeature: SidebarFeature.State
    var serverLifecycleFeature: ServerLifecycleFeature.State
    var welcome: WelcomeFeature.State = WelcomeFeature.State()
    @Presents var referenceServersAlert: AlertState<Action.Alert>?

    @Shared(.inMemory("servers"))
    var servers: IdentifiedArrayOf<ServerFeature.State> = []

    @FetchAll(MCPServer.all)
    var fetchedServers: [MCPServer] = []

    init() {
      let servers = Shared(value: IdentifiedArrayOf<ServerFeature.State>())
      self._servers = servers
      self._sidebarFeature = SidebarFeature.State(servers: servers)
      self._serverLifecycleFeature = ServerLifecycleFeature.State(servers: servers)
    }
  }

  enum Action {
    case onAppear
    case chatFeature(ChatFeature.Action)
    case sidebarFeature(SidebarFeature.Action)
    case serverLifecycleFeature(ServerLifecycleFeature.Action)
    case welcome(WelcomeFeature.Action)
    case syncServersFromDatabase
    case referenceServersAlert(PresentationAction<Alert>)
    case referenceServersAdded

    enum Alert: Equatable {}
    case addReferenceServers

  }

  var body: some ReducerOf<Self> {
    CombineReducers {
      Scope(state: \.chatFeature, action: \.chatFeature) {
        ChatFeature()
      }

      Scope(state: \.welcome, action: \.welcome) {
        WelcomeFeature()
      }

      Scope(state: \.sidebarFeature, action: \.sidebarFeature) {
        SidebarFeature()
      }

      Scope(state: \.serverLifecycleFeature, action: \.serverLifecycleFeature) {
        ServerLifecycleFeature()
      }

      coreReducer
    }
    .onChange(of: \.fetchedServers) { oldValue, newValue in
      Reduce { state, action in
        state.welcome.isVisible = newValue.isEmpty
        return .send(.syncServersFromDatabase)
      }
    }
    .ifLet(\.$referenceServersAlert, action: \.referenceServersAlert)
  }

  @ReducerBuilder<State, Action>
  private var coreReducer: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        // Set initial welcome visibility based on whether we have servers
        state.welcome.isVisible = state.fetchedServers.isEmpty
        return .send(.syncServersFromDatabase)

      case .chatFeature:
        return .none

      case let .serverLifecycleFeature(.serverFeature(.element(id: _, action: .tabSelected(tab)))):
        return .send(.sidebarFeature(.delegate(.currentServerTabChanged(tab))))

      case .serverLifecycleFeature:
        return .none

      case let .sidebarFeature(.delegate(.serverUpdated(serverId))):
        return .send(.serverLifecycleFeature(.reloadServerConnection(serverId)))

      case .sidebarFeature:
        return .none

      case .welcome(.importServersButtonTapped):
        return .send(.sidebarFeature(.importMenuItemTapped))

      case .welcome(.addServerButtonTapped):
        state.welcome.isVisible = false
        return .send(.sidebarFeature(.addServerButtonTapped))

      case .welcome(.addReferenceServersButtonTapped):
        return .send(.addReferenceServers)

      case .welcome:
        return .none

      case .syncServersFromDatabase:
        return handleSyncServersFromDatabase(&state)

      case .addReferenceServers:
        return handleAddReferenceServers(&state)

      case .referenceServersAlert:
        return .none

      case .referenceServersAdded:
        // Close welcome modal first
        state.welcome.isVisible = false

        state.referenceServersAlert = AlertState {
          TextState("Reference Servers Added")
        } actions: {
          ButtonState(role: .cancel) {
            TextState("OK")
          }
        } message: {
          TextState(
            "The reference servers have been added successfully.\n\nNote: These servers require npx and uvx to be installed. You can install both using Homebrew:\n\nbrew install node uv"
          )
        }

        // Force a sync to update the servers list
        return .send(.syncServersFromDatabase)
      }
    }
  }

  private func handleSyncServersFromDatabase(_ state: inout State) -> Effect<Action> {
    let isInitialLoad = state.servers.isEmpty
    let existingServerIds = Set(state.servers.map { $0.id })
    let fetchedServerIds = Set(state.fetchedServers.map { $0.id })

    let serversToAdd = state.fetchedServers.filter { !existingServerIds.contains($0.id) }
    let serverIdsToRemove = existingServerIds.subtracting(fetchedServerIds)

    state.$servers.withLock { servers in
      // Add new servers
      for server in serversToAdd {
        servers.append(ServerFeature.State(server: server))
      }

      // Remove deleted servers
      for serverId in serverIdsToRemove {
        servers.remove(id: serverId)
      }

      // Update existing servers
      for fetchedServer in state.fetchedServers {
        if var existingServer = servers[id: fetchedServer.id] {
          existingServer.server = fetchedServer
          servers[id: fetchedServer.id] = existingServer
        }
      }
    }

    var effects: [Effect<Action>] = []

    // Connect servers on initial load
    if isInitialLoad {
      // Let the sidebar handle initial server selection
      effects.append(.send(.sidebarFeature(.delegate(.initialServerLoad))))

      // Connect all servers
      for server in state.fetchedServers {
        effects.append(
          .send(.serverLifecycleFeature(.reloadServerConnection(server.id)))
        )
      }
    } else if !serversToAdd.isEmpty {
      // Connect newly added servers
      for server in serversToAdd {
        effects.append(
          .send(.serverLifecycleFeature(.reloadServerConnection(server.id)))
        )
      }

      // Let the sidebar handle selection of new servers
      let newServerIds = serversToAdd.map { $0.id }
      effects.append(.send(.sidebarFeature(.delegate(.newServersAdded(newServerIds)))))
    }

    return effects.isEmpty ? .none : .merge(effects)
  }

  private func handleAddReferenceServers(_ state: inout State) -> Effect<Action> {
    logger.info("Adding reference servers")

    // Get existing server names for duplicate checking
    let existingServerNames = Set(state.fetchedServers.map { $0.name })

    return .run { [database] send in
      do {
        let allReferenceServers = [
          MCPServer(
            id: UUID(),
            name: "everything",
            transport: .stdio,
            command: "npx",
            url: nil,
            args: ["-y", "@modelcontextprotocol/server-everything"],
            environment: nil,
            headers: nil
          ),
          MCPServer(
            id: UUID(),
            name: "fetch",
            transport: .stdio,
            command: "uvx",
            url: nil,
            args: ["mcp-server-fetch"],
            environment: nil,
            headers: nil
          ),
          MCPServer(
            id: UUID(),
            name: "git",
            transport: .stdio,
            command: "uvx",
            url: nil,
            args: ["mcp-server-git"],
            environment: nil,
            headers: nil
          ),
          MCPServer(
            id: UUID(),
            name: "memory",
            transport: .stdio,
            command: "npx",
            url: nil,
            args: ["-y", "@modelcontextprotocol/server-memory"],
            environment: nil,
            headers: nil
          ),
          MCPServer(
            id: UUID(),
            name: "sequential-thinking",
            transport: .stdio,
            command: "npx",
            url: nil,
            args: ["-y", "@modelcontextprotocol/server-sequential-thinking"],
            environment: nil,
            headers: nil
          ),
        ]

        // Filter out servers with duplicate names
        let referenceServers = allReferenceServers.filter { server in
          !existingServerNames.contains(server.name)
        }

        if referenceServers.isEmpty {
          logger.info("All reference servers already exist, skipping")
        } else {
          try await database.write { db in
            try MCPServer.insert { referenceServers }.execute(db)
          }
        }

        await send(.referenceServersAdded)
      } catch {
        logger.error("Failed to add reference servers: \(error)")
      }
    }
  }
}
