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

private enum SidebarError: LocalizedError {
  case serverNotFound

  var errorDescription: String? {
    switch self {
    case .serverNotFound:
      return "Server not found"
    }
  }
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
    case openAddServerWithDXT(tempDir: URL, manifest: DXTManifest, manifestData: Data)

    // Server CRUD operations
    case renameServer(id: UUID, newName: String)
    case proceedWithRename(serverId: UUID, newName: String)
    case showRenameError(String)
    case confirmDeleteServer(MCPServer)
    case serverUpdated(MCPServer, MCPServer)  // original, updated
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
      case openAddServerWithDXT(tempDir: URL, manifest: DXTManifest, manifestData: Data)
    }
  }

  @Dependency(\.serverStore) var serverStore

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
        return .none

      case let .openAddServerWithDXT(tempDir, manifest, manifestData):
        state.addServer = AddServerFeature.State()
        return .send(
          .addServer(
            .presented(
              .loadDXTFile(tempDir: tempDir, manifest: manifest, manifestData: manifestData)))
        )

      case .importMenuItemTapped:
        state.importWizard = ImportWizardFeature.State()
        return .none

      case let .editServerTapped(server):
        state.editServer = AddServerFeature.State(editingServer: server)
        return .none

      case let .deleteServerTapped(server):
        state.deleteConfirmation = deleteConfirmationAlert(for: server)
        return .none

      case let .renameServer(id: serverId, newName: newName):
        return .run { [serverStore] send in
          let validationResult = try await serverStore.validateServerName(
            newName,
            excludingServerID: serverId
          )

          switch validationResult {
          case .valid:
            await send(.proceedWithRename(serverId: serverId, newName: newName))
          case .invalid(let reason):
            await send(.showRenameError(reason))
          }
        }

      case let .proceedWithRename(serverId: serverId, newName: newName):
        return renameServerEffect(serverId: serverId, newName: newName, fetchedServers: state.fetchedServers)

      case let .showRenameError(reason):
        logger.warning("Rename failed: \(reason)")
        state.renameError = AlertState {
          TextState("Rename Failed")
        } actions: {
          ButtonState(role: .cancel) {
            TextState("OK")
          }
        } message: {
          TextState(reason)
        }
        return .none

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

      case let .serverUpdated(originalServer, updatedServer):
        let connectionPropertiesChanged =
          originalServer.transport != updatedServer.transport
          || originalServer.command != updatedServer.command
          || originalServer.url != updatedServer.url
          || originalServer.args != updatedServer.args
          || originalServer.environment != updatedServer.environment
          || originalServer.headers != updatedServer.headers
          || originalServer.dxtUserConfig != updatedServer.dxtUserConfig

        if !connectionPropertiesChanged {
          logger.debug("Server edited: only name changed")
          return .send(.serverRenamed(id: originalServer.id, newName: updatedServer.name))
        } else {
          logger.info("Server edited: connection properties changed")
          state.$servers.withLock { servers in
            if var serverState = servers[id: originalServer.id] {
              serverState.server = updatedServer
              servers[id: originalServer.id] = serverState
            }
          }
          return .send(.delegate(.serverUpdated(originalServer.id)))
        }

      case .importWizard(.dismiss):
        return .none

      case .importWizard:
        return .none

      case let .addServer(.presented(.serverSaved(.success(serverId)))):
        logger.info("New server added successfully with ID: \(serverId)")
        // Server is already saved in AddServerFeature, notify parent to sync
        return .send(.delegate(.serverAdded(serverId)))

      case let .editServer(.presented(.serverSaved(.success(serverId)))):
        logger.info("Server edited successfully with ID: \(serverId)")
        // Server is already updated in AddServerFeature, notify parent to sync
        return .send(.delegate(.serverUpdated(serverId)))

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

  private func renameServerEffect(serverId: UUID, newName: String, fetchedServers: [MCPServer]) -> Effect<Action> {
    .run { [serverStore] send in
      do {
        guard var server = fetchedServers.first(where: { $0.id == serverId }) else {
          throw SidebarError.serverNotFound
        }
        server.name = newName
        try await serverStore.updateServer(server)
        logger.info("Successfully renamed server")
        await send(.serverRenamed(id: serverId, newName: newName))
      } catch {
        await send(.serverUpdateResult(.failure(error)))
      }
    }
  }

  private func deleteServerEffect(server: MCPServer) -> Effect<Action> {
    .run { [serverStore] send in
      do {
        // ServerStore handles all cleanup: disconnection, OAuth tokens, keychain, DXT directories
        try await serverStore.deleteServer(server)
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

}
