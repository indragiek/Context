// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AsyncAlgorithms
import ComposableArchitecture
import ContextCore
import Foundation
import SharingGRDB
import os

struct ConnectionError: Equatable, Identifiable {
  let id = UUID()
  let error: String
  let timestamp: Date

  init(error: any Error) {
    self.error = error.localizedDescription
    self.timestamp = Date()
  }

  init(message: String) {
    self.error = message
    self.timestamp = Date()
  }
}

@Reducer
struct ServerFeature {
  let logger: Logger

  init(logger: Logger = Logger(subsystem: "com.indragie.Context", category: "ServerFeature")) {
    self.logger = logger
  }
  @ObservableState
  struct State: Equatable, Identifiable {
    let id: UUID
    var server: MCPServer
    var connectionState: Client.ConnectionState = .disconnected
    var connectionErrors: [ConnectionError] = []
    var selectedTab: ServerTab = .tools
    var toolsFeature: ToolsFeature.State
    var promptsFeature: PromptsFeature.State
    var resourcesFeature: ResourcesFeature.State
    var logsFeature: LogsFeature.State
    var hasInitiatedConnection = false
    var hasAttemptedReconnection = false
    var hasConnectedSuccessfully = false
    @Presents var authenticationState: AuthenticationFeature.State?

    init(server: MCPServer) {
      self.id = server.id
      self.server = server
      self.toolsFeature = ToolsFeature.State(server: server)
      self.promptsFeature = PromptsFeature.State(server: server)
      self.resourcesFeature = ResourcesFeature.State(server: server)
      self.logsFeature = LogsFeature.State(server: server)
    }
  }

  enum Action {
    case onAppear
    case onDisappear
    case startConnection
    case reloadConnection
    case disconnect
    case connectionStateChanged(Client.ConnectionState)
    case connectionError(any Error)
    case streamError(any Error)
    case connectionSucceeded
    case clearErrors
    case tabSelected(ServerTab)
    case pingTimer
    case pingFailed(any Error)
    case toolsFeature(ToolsFeature.Action)
    case promptsFeature(PromptsFeature.Action)
    case resourcesFeature(ResourcesFeature.Action)
    case logsFeature(LogsFeature.Action)
    case authenticationFeature(PresentationAction<AuthenticationFeature.Action>)
    case showAuthenticationSheet(
      serverID: UUID,
      serverName: String,
      serverURL: URL,
      resourceMetadataURL: URL,
      expiredToken: OAuthToken?,
      clientID: String?
    )
  }

  @Dependency(\.mcpClientManager) var mcpClientManager

  private enum CancelID: Hashable {
    case connectionStateSubscription(UUID)
    case errorStreamSubscription(UUID)
    case pingTimer(UUID)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.toolsFeature, action: \.toolsFeature) {
      ToolsFeature()
    }

    Scope(state: \.promptsFeature, action: \.promptsFeature) {
      PromptsFeature()
    }

    Scope(state: \.resourcesFeature, action: \.resourcesFeature) {
      ResourcesFeature()
    }

    Scope(state: \.logsFeature, action: \.logsFeature) {
      LogsFeature()
    }

    Reduce { state, action in
      switch action {
      case .onAppear:
        guard !state.hasInitiatedConnection else { return .none }

        state.hasInitiatedConnection = true

        return .run { [server = state.server] send in
          do {
            _ = try await mcpClientManager.createUnconnectedClient(for: server)
            await send(.startConnection)
          } catch {
            await send(.connectionError(error))
          }
        }

      case .startConnection:
        return .merge(
          .run { [server = state.server] send in
            guard let client = await mcpClientManager.existingClient(for: server) else {
              logger.warning(
                "No client found for server \(server.name) when setting up connection state subscription"
              )
              return
            }

            let connectionStateStream = await client.connectionState
            for await connectionState in connectionStateStream {
              await send(.connectionStateChanged(connectionState))
            }
          }
          .cancellable(id: CancelID.connectionStateSubscription(state.server.id)),

          .run { [server = state.server] send in
            guard let client = await mcpClientManager.existingClient(for: server) else {
              logger.warning(
                "No client found for server \(server.name) when setting up error stream subscription"
              )
              return
            }

            let errorStream = await client.streamErrors
            for await error in errorStream {
              await send(.streamError(error))
            }
          }
          .cancellable(id: CancelID.errorStreamSubscription(state.server.id)),

          .run { [server = state.server] send in
            guard let client = await mcpClientManager.existingClient(for: server) else {
              logger.warning(
                "No client found for server \(server.name) when initiating connection")
              return
            }

            do {
              logger.debug("Connecting to server \(server.name)")
              try await client.connect()
              logger.debug("Connected to server \(server.name), sending ping")
              try await client.ping()
              logger.info("Successfully connected to server \(server.name)")
              await send(.connectionSucceeded)
            } catch {
              logger.error("Failed to connect to server \(server.name): \(error)")
              await send(.connectionError(error))
            }
          }
        )

      case .onDisappear:
        return .merge(
          .cancel(id: CancelID.connectionStateSubscription(state.server.id)),
          .cancel(id: CancelID.errorStreamSubscription(state.server.id)),
          .cancel(id: CancelID.pingTimer(state.server.id))
        )

      case let .connectionStateChanged(connectionState):
        state.connectionState = connectionState
        switch connectionState {
        case .connected:
          state.connectionErrors = []
          state.hasAttemptedReconnection = false
          return .none
        case .disconnected:
          return .merge(
            .cancel(id: CancelID.pingTimer(state.server.id)),
            .send(.toolsFeature(.connectionStateChanged(connectionState))),
            .send(.promptsFeature(.connectionStateChanged(connectionState))),
            .send(.resourcesFeature(.connectionStateChanged(connectionState)))
          )
        case .connecting, .disconnecting:
          return .none
        }

      case let .connectionError(error):
        // Check if it's an authentication error
        if let streamableError = error as? StreamableHTTPTransportError,
          case let .authenticationRequired(resourceMetadataURL, _) = streamableError,
          state.server.transport == .streamableHTTP
        {
          let serverID = state.server.id
          let serverName = state.server.name
          guard let urlString = state.server.url,
            let serverURL = URL(string: urlString)
          else {
            // This shouldn't happen with valid data, but handle gracefully
            state.connectionErrors.append(
              ConnectionError(message: "Invalid server URL configuration"))
            state.connectionState = .disconnected
            return .none
          }

          return .run { send in
            // Check if we have an expired token with a refresh token
            let keychainManager = KeychainManager()
            let storedToken = try? await keychainManager.retrieveStoredToken(for: serverID)

            await send(
              .showAuthenticationSheet(
                serverID: serverID,
                serverName: serverName,
                serverURL: serverURL,
                resourceMetadataURL: resourceMetadataURL,
                expiredToken: storedToken?.token,
                clientID: storedToken?.clientID
              ))
          }
        }

        state.connectionErrors.append(ConnectionError(error: error))
        state.connectionState = .disconnected
        state.hasInitiatedConnection = false
        state.hasAttemptedReconnection = false
        return .merge(
          .cancel(id: CancelID.pingTimer(state.server.id)),
          .send(.toolsFeature(.loadingFailed(error))),
          .send(.promptsFeature(.loadingFailed(error))),
          .send(.resourcesFeature(.loadingFailed(error)))
        )

      case let .streamError(error):
        state.connectionErrors.append(ConnectionError(error: error))

        if !state.hasConnectedSuccessfully {
          return .merge(
            .send(.toolsFeature(.loadingFailed(error))),
            .send(.promptsFeature(.loadingFailed(error))),
            .send(.resourcesFeature(.loadingFailed(error)))
          )
        }

        if error.isLikelyConnectionError {
          state.connectionState = .disconnected
          state.hasInitiatedConnection = false
          return .cancel(id: CancelID.pingTimer(state.server.id))
        }

        return .none

      case .connectionSucceeded:
        state.hasConnectedSuccessfully = true
        state.hasAttemptedReconnection = false
        return .merge(
          .send(.toolsFeature(.onConnected)),
          .send(.promptsFeature(.onConnected)),
          .send(.resourcesFeature(.onConnected)),
          .send(.logsFeature(.onConnected)),
          .run { send in
            while true {
              try await Task.sleep(for: .seconds(5))
              await send(.pingTimer)
            }
          }
          .cancellable(id: CancelID.pingTimer(state.server.id))
        )

      case .reloadConnection:
        guard state.connectionState != .disconnecting && state.connectionState != .connecting else {
          return .none
        }

        state.connectionState = .disconnecting
        state.connectionErrors = []
        state.hasInitiatedConnection = false
        state.hasAttemptedReconnection = false
        state.hasConnectedSuccessfully = false

        state.toolsFeature.isLoading = true
        state.promptsFeature.isLoading = true
        state.resourcesFeature.isLoading = true
        state.toolsFeature.error = nil
        state.promptsFeature.error = nil
        state.resourcesFeature.error = nil

        return .merge(
          .cancel(id: CancelID.connectionStateSubscription(state.server.id)),
          .cancel(id: CancelID.errorStreamSubscription(state.server.id)),
          .cancel(id: CancelID.pingTimer(state.server.id)),
          .send(.toolsFeature(.clearState)),
          .send(.promptsFeature(.clearState)),
          .send(.resourcesFeature(.clearState)),
          .run { [server = state.server] send in
            do {
              if await mcpClientManager.existingClient(for: server) != nil {
                try await mcpClientManager.disconnect(server: server)
              }
              await send(.onAppear)
            } catch {
              await send(.connectionError(error))
            }
          }
          .cancellable(
            id: CancelID.connectionStateSubscription(state.server.id), cancelInFlight: true)
        )

      case .clearErrors:
        state.connectionErrors = []
        return .none

      case .disconnect:
        state.connectionState = .disconnecting
        state.hasConnectedSuccessfully = false
        state.hasInitiatedConnection = false
        return .merge(
          .cancel(id: CancelID.connectionStateSubscription(state.server.id)),
          .cancel(id: CancelID.errorStreamSubscription(state.server.id)),
          .cancel(id: CancelID.pingTimer(state.server.id)),
          .run { [server = state.server] send in
            do {
              try await mcpClientManager.disconnect(server: server)
              await send(.connectionStateChanged(.disconnected))
            } catch {
              await send(.connectionError(error))
            }
          }
        )

      case let .tabSelected(tab):
        state.selectedTab = tab
        return .none

      case .pingTimer:
        return .run { [server = state.server] send in
          do {
            guard let client = await mcpClientManager.existingClient(for: server) else {
              return
            }

            let connectionState = await client.currentConnectionState
            guard connectionState == .connected else {
              return
            }

            try await client.ping()
          } catch {
            await send(.pingFailed(error))
          }
        }

      case let .pingFailed(error):
        state.connectionErrors.append(ConnectionError(error: error))

        if state.hasConnectedSuccessfully && !state.hasAttemptedReconnection {
          state.hasAttemptedReconnection = true
          logger.info("Ping failed, attempting reconnection")
          return .send(.reloadConnection)
        }

        return .none

      case .toolsFeature(.reconnect), .promptsFeature(.reconnect), .resourcesFeature(.reconnect):
        switch action {
        case .toolsFeature(.reconnect):
          state.toolsFeature.error = nil
          state.toolsFeature.isLoading = true
        case .promptsFeature(.reconnect):
          state.promptsFeature.error = nil
          state.promptsFeature.isLoading = true
        case .resourcesFeature(.reconnect):
          state.resourcesFeature.error = nil
          state.resourcesFeature.isLoading = true
        default:
          break
        }

        return .send(.reloadConnection)

      case .toolsFeature, .promptsFeature, .resourcesFeature, .logsFeature:
        return .none

      case let .showAuthenticationSheet(
        serverID, serverName, serverURL, resourceMetadataURL, expiredToken, clientID):
        // Show authentication sheet with optional expired token
        state.authenticationState = AuthenticationFeature.State(
          serverID: serverID,
          serverName: serverName,
          serverURL: serverURL,
          resourceMetadataURL: resourceMetadataURL,
          expiredToken: expiredToken,
          clientID: clientID
        )
        return .none

      case .authenticationFeature(.presented(.authenticationCompleteAndDismiss)):
        // Authentication is complete but let the child handle dismissal
        state.hasInitiatedConnection = false
        return .none

      case .authenticationFeature(.dismiss):
        // Modal is being dismissed
        state.authenticationState = nil
        // If hasInitiatedConnection is false, it means auth succeeded
        if !state.hasInitiatedConnection {
          // Tell child features to prepare for reconnection
          return .merge(
            .send(.toolsFeature(.prepareForReconnection)),
            .send(.promptsFeature(.prepareForReconnection)),
            .send(.resourcesFeature(.prepareForReconnection)),
            .send(.startConnection)
          )
        }
        return .none

      case .authenticationFeature:
        return .none
      }
    }
    .ifLet(\.$authenticationState, action: \.authenticationFeature) {
      AuthenticationFeature()
    }
  }
}

enum ServerTab: String, CaseIterable, Hashable {
  case tools = "Tools"
  case prompts = "Prompts"
  case resources = "Resources"
  case logs = "Logs"
}
