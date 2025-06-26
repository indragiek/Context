// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation
import GRDB
import SharingGRDB
import SwiftUI
import os

enum SidebarItem: Equatable, Hashable {
  case chat
  case server(id: UUID)
}

@Reducer
struct SidebarFeature {
  let logger: Logger

  init(logger: Logger = Logger(subsystem: "com.indragie.Context", category: "SidebarFeature")) {
    self.logger = logger
  }

  @ObservableState
  struct State: Equatable {
    @Shared var servers: IdentifiedArrayOf<ServerFeature.State>
    @Presents var importWizard: ImportWizardFeature.State?
    @Presents var addServer: AddServerFeature.State?
    @Presents var editServer: AddServerFeature.State?
    @Presents var deleteConfirmation: AlertState<Action.Alert>?
    @Presents var renameError: AlertState<Action.Alert>?

    @FetchAll(MCPServer.all)
    var fetchedServers: [MCPServer] = []

    var serverDeletedID: UUID?
    var selectedSidebarItem: SidebarItem?
    var selectedServerID: UUID?
    var currentServerTab: ServerTab = .tools

    init(servers: Shared<IdentifiedArrayOf<ServerFeature.State>>) {
      self._servers = servers
    }
  }

  enum Action {
    // User interactions
    case addServerButtonTapped
    case importMenuItemTapped
    case editServerTapped(MCPServer)
    case deleteServerTapped(MCPServer)
    case sidebarItemSelected(SidebarItem)
    case serverSelected(UUID)

    // Server CRUD operations
    case renameServer(id: UUID, newName: String)
    case confirmDeleteServer(MCPServer)
    case serverAdded(MCPServer)
    case serverRenamed(id: UUID, newName: String)

    // Operation results
    case serverUpdateResult(Result<Void, any Error>)
    case serverDeleteResult(Result<Void, any Error>)

    // Presentation actions
    case importWizard(PresentationAction<ImportWizardFeature.Action>)
    case addServer(PresentationAction<AddServerFeature.Action>)
    case editServer(PresentationAction<AddServerFeature.Action>)
    case deleteConfirmation(PresentationAction<Alert>)
    case renameError(PresentationAction<Alert>)

    // Delegate actions
    case delegate(Delegate)

    enum Alert: Equatable {
      case confirmDelete(MCPServer)
    }

    enum Delegate: Equatable {
      case serverUpdated(UUID)
      case currentServerTabChanged(ServerTab)
      case initialServerLoad
      case newServersAdded([UUID])
      case serverAdded(UUID)
    }
  }

  @Dependency(\.defaultDatabase) var database
  @Dependency(\.mcpClientManager) var mcpClientManager

  var body: some ReducerOf<Self> {
    CombineReducers {
      coreReducer
    }
    .ifLet(\.$importWizard, action: \.importWizard) {
      ImportWizardFeature()
    }
    .ifLet(\.$addServer, action: \.addServer) {
      AddServerFeature()
    }
    .ifLet(\.$editServer, action: \.editServer) {
      AddServerFeature()
    }
    .ifLet(\.$deleteConfirmation, action: \.deleteConfirmation)
    .ifLet(\.$renameError, action: \.renameError)
  }

  @ReducerBuilder<State, Action>
  private var coreReducer: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .addServerButtonTapped:
        state.addServer = AddServerFeature.State()
        let existingNames = Set(state.servers.map { $0.server.name })
        return .send(.addServer(.presented(.setExistingServerNames(existingNames))))

      case .importMenuItemTapped:
        state.importWizard = ImportWizardFeature.State()
        return .none

      case let .editServerTapped(server):
        state.editServer = AddServerFeature.State(editingServer: server)
        let existingNames = Set(state.servers.map { $0.server.name })
        return .send(.editServer(.presented(.setExistingServerNames(existingNames))))

      case let .deleteServerTapped(server):
        state.deleteConfirmation = deleteConfirmationAlert(for: server)
        return .none

      case let .renameServer(id: serverId, newName: newName):
        let existingNames = state.servers
          .filter { $0.id != serverId }
          .map { $0.server.name }

        if existingNames.contains(newName) {
          logger.warning("Rename failed: Server with that name already exists")
          state.renameError = AlertState {
            TextState("Rename Failed")
          } actions: {
            ButtonState(role: .cancel) {
              TextState("OK")
            }
          } message: {
            TextState(
              "A server with the name \"" + newName
                + "\" already exists. Please choose a different name."
            )
          }
          return .none
        }

        return renameServerEffect(serverId: serverId, newName: newName)

      case let .confirmDeleteServer(server):
        logger.info("Deleting server")
        state.serverDeletedID = server.id

        if state.selectedServerID == server.id {
          let serverIds = state.servers.map { $0.id }
          if let currentIndex = serverIds.firstIndex(of: server.id) {
            if currentIndex + 1 < serverIds.count {
              state.selectedServerID = serverIds[currentIndex + 1]
              state.selectedSidebarItem = .server(id: serverIds[currentIndex + 1])
            } else if currentIndex > 0 {
              state.selectedServerID = serverIds[currentIndex - 1]
              state.selectedSidebarItem = .server(id: serverIds[currentIndex - 1])
            } else {
              state.selectedServerID = nil
              state.selectedSidebarItem = nil
            }
          }
        }

        return deleteServerEffect(server: server)

      case let .serverRenamed(id: serverId, newName: newName):
        state.$servers.withLock { servers in
          if var server = servers[id: serverId] {
            server.server.name = newName
            servers[id: serverId] = server
          }
        }
        return .none

      case .serverUpdateResult(.failure):
        logger.error("Server update failed")
        return .none

      case .serverUpdateResult(.success):
        return .none

      case .serverDeleteResult(.failure):
        logger.error("Server delete failed")
        return .none

      case .serverDeleteResult(.success):
        if let deletedID = state.serverDeletedID {
          _ = state.$servers.withLock { servers in
            servers.remove(id: deletedID)
          }
        }
        state.serverDeletedID = nil
        return .none

      case let .serverAdded(server):
        _ = state.$servers.withLock { servers in
          servers.append(ServerFeature.State(server: server))
        }
        return .merge(
          .send(.serverSelected(server.id)),
          .send(.delegate(.serverAdded(server.id)))
        )

      case .importWizard(.dismiss):
        return .none

      case .importWizard:
        return .none

      case let .addServer(.presented(.serverSaved(.success(serverId)))):
        logger.info("New server added successfully with ID: \(serverId)")
        return .run { [database] send in
          do {
            let server = try await database.read { db in
              try MCPServer.where { $0.id == serverId }.fetchOne(db)
            }
            if let server = server {
              await send(.serverAdded(server))
            }
          } catch {
            logger.error("Failed to fetch newly added server: \(error)")
          }
        }

      case .editServer(.presented(.serverSaved(.success(_)))):
        if let editState = state.editServer,
          case .edit(let originalServer) = editState.mode
        {
          let editedServer = createServer(from: editState)

          let connectionPropertiesChanged =
            originalServer.transport != editedServer.transport
            || originalServer.command != editedServer.command
            || originalServer.url != editedServer.url || originalServer.args != editedServer.args
            || originalServer.environment != editedServer.environment
            || originalServer.headers != editedServer.headers

          if !connectionPropertiesChanged {
            logger.debug("Server edited: only name changed")
            return .send(.serverRenamed(id: originalServer.id, newName: editedServer.name))
          } else {
            logger.info("Server edited: connection properties changed")
            state.$servers.withLock { servers in
              if var serverState = servers[id: originalServer.id] {
                serverState.server = editedServer
                servers[id: originalServer.id] = serverState
              }
            }
            return .send(.delegate(.serverUpdated(originalServer.id)))
          }
        }
        return .none

      case .addServer, .editServer:
        return .none

      case .deleteConfirmation(.presented(.confirmDelete(let server))):
        state.deleteConfirmation = nil
        return .send(.confirmDeleteServer(server))

      case .deleteConfirmation:
        return .none

      case .renameError:
        return .none

      case let .sidebarItemSelected(item):
        state.selectedSidebarItem = item
        if item == .chat {
          state.selectedServerID = nil
        }
        return .none

      case let .serverSelected(serverID):
        var serverExists = false
        state.$servers.withLock { servers in
          if var server = servers[id: serverID] {
            server.selectedTab = state.currentServerTab
            servers[id: serverID] = server
            serverExists = true
          }
        }

        if !serverExists {
          logger.warning("Attempted to select non-existent server")
          return .none
        }

        state.selectedServerID = serverID
        state.selectedSidebarItem = .server(id: serverID)
        return .none

      case let .delegate(.currentServerTabChanged(tab)):
        state.currentServerTab = tab
        return .none

      case .delegate(.initialServerLoad):
        if state.selectedServerID == nil, let firstServer = state.servers.first {
          return .send(.serverSelected(firstServer.id))
        }
        return .none

      case let .delegate(.newServersAdded(serverIds)):
        // Always select the first newly added server
        if let firstNewServerId = serverIds.first {
          return .send(.serverSelected(firstNewServerId))
        }
        return .none

      case .delegate:
        return .none
      }
    }
  }

  private func renameServerEffect(serverId: UUID, newName: String) -> Effect<Action> {
    .run { [database] send in
      do {
        try await database.write { db in
          let servers = try MCPServer.where { $0.id == serverId }.fetchAll(db)
          guard var server = servers.first else {
            throw AppError.serverNotFound
          }
          server.name = newName
          try MCPServer.update(server).execute(db)
        }
        logger.info("Successfully renamed server")
        await send(.serverRenamed(id: serverId, newName: newName))
      } catch {
        await send(.serverUpdateResult(.failure(error)))
      }
    }
  }

  private func deleteServerEffect(server: MCPServer) -> Effect<Action> {
    .run { [database, mcpClientManager] send in
      do {
        try? await mcpClientManager.disconnect(server: server)

        do {
          try await mcpClientManager.deleteToken(for: server)
          logger.info("Deleted OAuth token for server \(server.name)")
        } catch {
          logger.warning("Failed to delete OAuth token for server \(server.name): \(error)")
        }

        try await database.write { db in
          try MCPServer.delete().where { $0.id == server.id }.execute(db)
        }
        logger.info("Successfully deleted server")
        await send(.serverDeleteResult(.success(())))
      } catch {
        await send(.serverDeleteResult(.failure(error)))
      }
    }
  }

  private func deleteConfirmationAlert(for server: MCPServer) -> AlertState<Action.Alert> {
    AlertState {
      TextState("Delete Server")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDelete(server)) {
        TextState("Delete")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState(
        "Are you sure you want to delete \"" + server.name + "\"? This action cannot be undone.")
    }
  }

  private func createServer(from state: AddServerFeature.State) -> MCPServer {
    let id: UUID
    switch state.mode {
    case .add:
      id = UUID()
    case .edit(let originalServer):
      id = originalServer.id
    }

    var server = MCPServer(
      id: id,
      name: state.serverName,
      transport: state.transport
    )

    switch state.transport {
    case .stdio:
      server.command = state.command
      let filteredArgs = state.arguments.map { $0.value }.filter { !$0.isEmpty }
      server.args = filteredArgs.isEmpty ? nil : filteredArgs
      let validEnv = state.environmentVariables.filter { !$0.name.isEmpty && !$0.value.isEmpty }
      let envDict = Dictionary(uniqueKeysWithValues: validEnv.map { ($0.name, $0.value) })
      server.environment = envDict.isEmpty ? nil : envDict

    case .sse, .streamableHTTP:
      server.url = state.url
      let validHeaders = state.headers.filter { !$0.key.isEmpty && !$0.value.isEmpty }
      let headerDict = Dictionary(uniqueKeysWithValues: validHeaders.map { ($0.key, $0.value) })
      server.headers = headerDict.isEmpty ? nil : headerDict
    }

    return server
  }
}
