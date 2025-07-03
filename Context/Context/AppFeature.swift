// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation
import GRDB
import SharingGRDB
import SwiftUI
import os

@Reducer
struct AppFeature {
  private let logger: Logger

  init(logger: Logger = Logger(subsystem: "com.indragie.Context", category: "AppFeature")) {
    self.logger = logger
  }

  @Dependency(\.defaultDatabase) var database
  @Dependency(\.serverStore) var serverStore
  @Dependency(\.dxtStore) var dxtStore

  @ObservableState
  struct State: Equatable {
    var chatFeature = ChatFeature.State()
    var sidebarFeature: SidebarFeature.State
    var serverLifecycleFeature: ServerLifecycleFeature.State
    var welcome: WelcomeFeature.State = WelcomeFeature.State()
    @Presents var referenceServersAlert: AlertState<Action.Alert>?
    @Presents var dxtReplaceAlert: AlertState<Action.DXTReplaceAlert>?
    @Presents var errorAlert: AlertState<Action.Alert>?

    // Temporary storage for DXT data during replacement flow
    struct PendingDXTReplacement: Equatable, Sendable {
      let tempDir: URL
      let manifest: DXTManifest
      let manifestData: Data
    }
    var pendingDXTReplacement: PendingDXTReplacement?

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
    case openDXTFile(URL)
    case checkExistingDXTServer(url: URL, tempDir: URL, manifest: DXTManifest, manifestData: Data)
    case showDXTReplaceAlert(
      existingServer: MCPServer, newManifest: DXTManifest, tempDir: URL, manifestData: Data)
    case proceedWithAddingDXTServer(manifest: DXTManifest, tempDir: URL, manifestData: Data)
    case dxtReplaceAlert(PresentationAction<DXTReplaceAlert>)
    case errorAlert(PresentationAction<Alert>)
    case showError(any Error, title: String?)
    case showErrorAlert(title: String, message: String)

    enum Alert: Equatable {}
    enum DXTReplaceAlert: Equatable {
      case replace
      case cancel
    }
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
    .ifLet(\.$dxtReplaceAlert, action: \.dxtReplaceAlert)
    .ifLet(\.$errorAlert, action: \.errorAlert)
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
        // Sync database first to ensure the server updates are available
        return .merge(
          .send(.syncServersFromDatabase),
          .send(.serverLifecycleFeature(.reloadServerConnection(serverId)))
        )

      case let .sidebarFeature(.delegate(.serverAdded(serverId))):
        // Sync database first to ensure the server is available
        return .merge(
          .send(.syncServersFromDatabase),
          .send(.serverLifecycleFeature(.reloadServerConnection(serverId)))
        )

      case let .sidebarFeature(.delegate(.openAddServerWithDXT(tempDir, manifest, manifestData))):
        // Forward to SidebarFeature to open Add Server modal with DXT
        return .send(
          .sidebarFeature(
            .openAddServerWithDXT(tempDir: tempDir, manifest: manifest, manifestData: manifestData))
        )

      case .sidebarFeature(.delegate(.serverImportCompleted)):
        return .send(.syncServersFromDatabase)
        
      case .sidebarFeature:
        return .none

      case .welcome(.importServersButtonTapped):
        state.welcome.isVisible = false
        return .send(.sidebarFeature(.importMenuItemTapped))

      case .welcome(.addServerButtonTapped):
        state.welcome.isVisible = false
        return .send(.sidebarFeature(.addServerButtonTapped))

      case .welcome(.addReferenceServersButtonTapped):
        state.welcome.isVisible = false
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

      case let .openDXTFile(url):
        return .run { [dxtStore] send in
          do {
            let result = try await dxtStore.processFile(at: url)
            await send(
              .checkExistingDXTServer(
                url: url,
                tempDir: result.tempDir,
                manifest: result.manifest,
                manifestData: result.manifestData))
          } catch {
            logger.error("Failed to open DXT file: \(error)")
            await send(.showError(error, title: "Failed to Open DXT File"))
          }
        }

      case let .checkExistingDXTServer(_, tempDir, manifest, manifestData):
        // Check if there's an existing server with the same name
        let serverName = manifest.displayName ?? manifest.name

        return .run { [serverStore, dxtStore, logger] send in
          do {
            // Query for existing DXT server with the same name
            let existingServer = try await serverStore.findServer(
              name: serverName,
              transport: .dxt
            )

            if let existingServer = existingServer {
              await send(
                .showDXTReplaceAlert(
                  existingServer: existingServer,
                  newManifest: manifest,
                  tempDir: tempDir,
                  manifestData: manifestData))
            } else {
              // No existing server, proceed with adding
              await send(
                .proceedWithAddingDXTServer(
                  manifest: manifest,
                  tempDir: tempDir,
                  manifestData: manifestData))
            }
          } catch {
            logger.error("Failed to check for existing server: \(error)")
            dxtStore.cleanupTempDirectory(tempDir)
            await send(.showError(error, title: "Failed to Check Server"))
          }
        }

      case let .showDXTReplaceAlert(existingServer, newManifest, tempDir, manifestData):
        let existingVersion = dxtStore.getServerVersion(existingServer)
        let newVersion = newManifest.version

        // Store the pending replacement data
        state.pendingDXTReplacement = State.PendingDXTReplacement(
          tempDir: tempDir,
          manifest: newManifest,
          manifestData: manifestData
        )

        // Build a better version display string
        let existingVersionDisplay = existingVersion ?? "No version information"
        let versionComparison =
          existingVersion != nil && existingVersion != newVersion
          ? "\n\nExisting version: \(existingVersionDisplay)\nNew version: \(newVersion)"
          : "\n\nVersion: \(newVersion)"

        state.dxtReplaceAlert = AlertState {
          TextState("Replace Existing Server?")
        } actions: {
          ButtonState(action: .replace) {
            TextState("Replace")
          }
          ButtonState(role: .cancel, action: .cancel) {
            TextState("Cancel")
          }
        } message: {
          TextState(
            """
            A server named "\(existingServer.name)" already exists.\(versionComparison)

            Do you want to replace the existing server?
            """)
        }

        return .none

      case let .dxtReplaceAlert(.presented(action)):
        switch action {
        case .replace:
          // Get the pending replacement data
          guard let replacement = state.pendingDXTReplacement else {
            return .none
          }

          // Find the existing server to delete
          guard
            let existingServer = state.fetchedServers.first(where: {
              $0.name == replacement.manifest.name
            })
          else {
            return .none
          }

          // Clear the alert and pending data
          state.dxtReplaceAlert = nil
          state.pendingDXTReplacement = nil

          return .run { [serverStore, dxtStore, logger] send in
            do {
              // Delete the existing server (handles disconnection, OAuth, keychain, etc.)
              try await serverStore.deleteServer(existingServer)

              // Sync database changes before proceeding
              await send(.syncServersFromDatabase)

              // After successful deletion, proceed with adding the new server
              await send(
                .checkExistingDXTServer(
                  url: URL(fileURLWithPath: ""),  // URL not needed anymore
                  tempDir: replacement.tempDir,
                  manifest: replacement.manifest,
                  manifestData: replacement.manifestData
                ))

            } catch {
              logger.error("Failed to delete existing server: \(error)")
              // Clean up on failure
              dxtStore.cleanupTempDirectory(replacement.tempDir)
              await send(.showError(error, title: "Failed to Replace Server"))
            }
          }

        case .cancel:
          // User cancelled - clean up temp directory
          if let replacement = state.pendingDXTReplacement {
            dxtStore.cleanupTempDirectory(replacement.tempDir)
          }
          state.pendingDXTReplacement = nil
          return .none
        }

      case let .proceedWithAddingDXTServer(manifest, tempDir, manifestData):
        return handleAddDXTServer(
          manifest: manifest, tempDir: tempDir, manifestData: manifestData, state: &state)

      case .dxtReplaceAlert(.dismiss):
        // Clean up pending replacement if user dismisses the alert
        if let replacement = state.pendingDXTReplacement {
          dxtStore.cleanupTempDirectory(replacement.tempDir)
          state.pendingDXTReplacement = nil
        }
        return .none

      case .dxtReplaceAlert:
        return .none

      case let .showError(error, customTitle):
        // Check if error conforms to LocalizedError
        if let localizedError = error as? (any LocalizedError) {
          let title = localizedError.errorDescription ?? customTitle ?? "Error"
          var messageComponents: [String] = []

          if let failureReason = localizedError.failureReason {
            messageComponents.append(failureReason)
          }

          if let recoverySuggestion = localizedError.recoverySuggestion {
            messageComponents.append(recoverySuggestion)
          }

          let message =
            messageComponents.isEmpty
            ? error.localizedDescription
            : messageComponents.joined(separator: "\n\n")

          return .send(.showErrorAlert(title: title, message: message))
        } else {
          // For non-LocalizedError, use custom title or default, and localizedDescription
          let title = customTitle ?? "Error"
          return .send(.showErrorAlert(title: title, message: error.localizedDescription))
        }

      case let .showErrorAlert(title, message):
        state.errorAlert = AlertState {
          TextState(title)
        } actions: {
          ButtonState(role: .cancel) {
            TextState("OK")
          }
        } message: {
          TextState(message)
        }
        return .none

      case .errorAlert:
        return .none
      }
    }
  }

  private func handleAddDXTServer(
    manifest: DXTManifest, tempDir: URL, manifestData: Data, state: inout State
  ) -> Effect<Action> {
    // Check if the server requires user configuration
    if dxtStore.requiresUserConfiguration(manifest) {
      // Open Add Server modal with DXT pre-selected
      state.welcome.isVisible = false
      return .send(
        .sidebarFeature(
          .delegate(
            .openAddServerWithDXT(tempDir: tempDir, manifest: manifest, manifestData: manifestData))
        ))
    } else {
      // Automatically add the server
      let serverID = UUID()
      return .run { [serverStore, dxtStore, logger, serverID] send in
        do {
          // Install the DXT server using the server ID as directory name
          let serverDir = try await dxtStore.installServer(
            from: tempDir,
            serverID: serverID,
            mode: .add
          )

          // Create the server record
          let server = dxtStore.createServer(
            from: manifest,
            serverID: serverID,
            installPath: serverDir
          )

          // Save to database
          try await serverStore.createServer(server)

          // Manually trigger sync to reload servers and select the new one
          await send(.syncServersFromDatabase)

        } catch {
          logger.error("Failed to add DXT server: \(error)")
          // Clean up temp directory on failure
          dxtStore.cleanupTempDirectory(tempDir)
          await send(.showError(error, title: "Failed to Add DXT Server"))
        }
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
