// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Dependencies
import Foundation
import IdentifiedCollections
import SharingGRDB
import os

// Import Schema types
typealias Implementation = ContextCore.Implementation

/// Manages MCP client connections, ensuring only one client exists per server
actor MCPClientManager {
  private var clients: [UUID: Client] = [:]
  private let logger = Logger(subsystem: "com.indragie.Context", category: "MCPClientManager")
  private let keychainManager = KeychainManager()

  // Token refresh state
  private var refreshTask: Task<Void, Never>?
  private var activeRefreshTasks: [UUID: Task<OAuthToken, any Error>] = [:]
  private let refreshCheckInterval: TimeInterval = 60  // Check every minute
  private let refreshBeforeExpiration: TimeInterval = 300  // Refresh 5 minutes before expiration

  @Dependency(\.oauthClient) var oauthClient
  @Dependency(\.defaultDatabase) var database

  init() {
    // Timer will be started on first access
  }

  /// Gets or creates a client for the specified server
  func client(for server: MCPServer) async throws -> Client {
    ensureTokenRefreshTimerStarted()

    if let existingClient = clients[server.id] {
      return existingClient
    }

    let client = try await createClient(for: server)
    clients[server.id] = client
    return client
  }

  /// Creates a client without connecting it
  func createUnconnectedClient(for server: MCPServer) async throws -> Client {
    if let existingClient = clients[server.id] {
      return existingClient
    }

    let transport = try await createTransport(for: server)
    let client = Client(transport: transport, logger: logger)
    clients[server.id] = client
    return client
  }

  /// Disconnects a client for the specified server
  func disconnect(server: MCPServer) async throws {
    guard let client = clients[server.id] else { return }

    try await client.disconnect()
    clients[server.id] = nil
  }

  /// Disconnects all clients
  func disconnectAll() async throws {
    for (_, client) in clients {
      try await client.disconnect()
    }
    clients.removeAll()
  }

  /// Gets the current connection state for a server
  func connectionState(for serverId: UUID) async -> Client.ConnectionState {
    guard let client = clients[serverId] else { return .disconnected }
    return await client.currentConnectionState
  }

  /// Gets an existing client if one exists, without creating a new one
  func existingClient(for server: MCPServer) async -> Client? {
    return clients[server.id]
  }

  /// Stores an OAuth token for a server.
  func storeToken(for server: MCPServer, token: OAuthToken, clientID: String) async throws {
    try await keychainManager.storeToken(for: server.id, token: token, clientID: clientID)

    if let client = clients[server.id],
      let transport = await client.transport as? StreamableHTTPTransport
    {
      await transport.setAuthorizationToken(token.accessToken)
      logger.info("Updated OAuth token for connected server \(server.name)")
    }
  }

  /// Retrieves the stored OAuth token for a server.
  func retrieveToken(for server: MCPServer) async throws -> OAuthToken? {
    return try await keychainManager.retrieveToken(for: server.id)
  }

  /// Deletes the stored OAuth token for a server.
  func deleteToken(for server: MCPServer) async throws {
    try await keychainManager.deleteToken(for: server.id)

    if let client = clients[server.id],
      let transport = await client.transport as? StreamableHTTPTransport
    {
      await transport.setAuthorizationToken(nil)
      logger.info("Cleared OAuth token for connected server \(server.name)")
    }
  }

  // MARK: - Private

  private func createClient(for server: MCPServer) async throws -> Client {
    let transport = try await createTransport(for: server)
    let client = Client(transport: transport, logger: logger)

    do {
      try await client.connect()
      return client
    } catch let error as StreamableHTTPTransportError {
      if case .authenticationRequired = error {
        if let existingToken = try? await keychainManager.retrieveToken(for: server.id),
          existingToken.isExpired,
          existingToken.refreshToken != nil
        {
          logger.info("Token expired for server \(server.name), attempting refresh")
          throw error
        }
      }
      throw error
    }
  }

  private func createTransport(for server: MCPServer) async throws -> any Transport {
    let clientInfo = Implementation(name: "Context", version: "1.0.0")
    var clientCapabilities = ClientCapabilities()
    clientCapabilities.roots = ClientCapabilities.Roots(listChanged: true)

    switch server.transport {
    case .stdio:
      guard let command = server.command else {
        throw MCPClientError.missingCommand
      }

      let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
      var shellArgs = ["-l", "-c"]

      var commandString = command
      if let args = server.args, !args.isEmpty {
        let escapedArgs = args.map { arg in
          "'" + arg.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        }.joined(separator: " ")
        commandString += " " + escapedArgs
      }
      shellArgs.append(commandString)

      let processInfo = StdioTransport.ServerProcessInfo(
        executableURL: URL(fileURLWithPath: shellPath),
        arguments: shellArgs,
        environment: server.environment
      )

      return StdioTransport(
        serverProcessInfo: processInfo,
        clientInfo: clientInfo,
        clientCapabilities: clientCapabilities,
        logger: logger
      )

    case .sse, .streamableHTTP:
      // SSE is deprecated and uses the same transport as streamableHTTP
      guard let urlString = server.url,
        let url = URL(string: urlString)
      else {
        throw MCPClientError.invalidURL
      }

      let configuration = URLSessionConfiguration.default
      if let headers = server.headers {
        configuration.httpAdditionalHeaders = headers
      }

      let transport = StreamableHTTPTransport(
        serverURL: url,
        urlSessionConfiguration: configuration,
        clientInfo: clientInfo,
        clientCapabilities: clientCapabilities,
        logger: logger
      )

      if let token = try? await keychainManager.retrieveToken(for: server.id) {
        if !token.isExpired {
          await transport.setAuthorizationToken(token.accessToken)
          logger.info("Set existing OAuth token for server \(server.name)")
        } else {
          logger.info("Existing OAuth token for server \(server.name) has expired")
          // Clean up expired token
          try? await keychainManager.deleteToken(for: server.id)
        }
      }

      return transport

    case .dxt:
      guard let urlString = server.url,
        let dxtDirectoryURL = URL(string: urlString)
      else {
        throw MCPClientError.invalidURL
      }
      
      // Resolve user config from keychain if needed
      var resolvedUserConfig: DXTUserConfigurationValues?
      if let userConfig = server.dxtUserConfig {
        let dxtConfigKeychain = DXTConfigKeychain()
        resolvedUserConfig = try await userConfig.resolvingKeychainReferences { uuid in
          try await dxtConfigKeychain.retrieveValue(for: uuid)
        }
        
        // Check if any values were missing from keychain
        let originalKeys = Set(userConfig.values.keys)
        let resolvedKeys: Set<String>
        if let resolved = resolvedUserConfig {
          resolvedKeys = Set(resolved.values.keys)
        } else {
          resolvedKeys = Set()
        }
        let missingKeys = originalKeys.subtracting(resolvedKeys)
        
        if !missingKeys.isEmpty {
          // Update the database to remove references to missing keys
          var cleanedConfig = userConfig
          for missingKey in missingKeys {
            cleanedConfig.values.removeValue(forKey: missingKey)
          }
          
          // Update server in database
          var updatedServer = server
          updatedServer.dxtUserConfig = cleanedConfig.values.isEmpty ? nil : cleanedConfig
          let serverToUpdate = updatedServer
          try await database.write { db in
            try MCPServer.update(serverToUpdate).execute(db)
          }
          
          // Throw error indicating which field needs to be configured
          let firstMissing = missingKeys.sorted().first ?? "unknown"
          throw MCPClientError.missingConfiguration(
            "Missing configuration value for '\(firstMissing)'. Please edit the server and provide this value."
          )
        }
      }

      return try await DXTTransport(
        dxtDirectory: dxtDirectoryURL,
        clientInfo: clientInfo,
        clientCapabilities: clientCapabilities,
        userConfig: resolvedUserConfig
      )
    }
  }

  // MARK: - Token Refresh

  private func startTokenRefreshTimer() {
    refreshTask = Task {
      while !Task.isCancelled {
        await checkAndRefreshTokens()
        try? await Task.sleep(for: .seconds(Int(refreshCheckInterval)))
      }
    }
  }

  private func ensureTokenRefreshTimerStarted() {
    if refreshTask == nil {
      startTokenRefreshTimer()
    }
  }

  private func checkAndRefreshTokens() async {
    logger.info("Checking tokens for refresh")

    // Get all servers from database
    guard
      let servers = try? await database.read({ db in
        try MCPServer.all.fetchAll(db)
      })
    else {
      logger.error("Failed to fetch servers for token refresh")
      return
    }

    // Check each server's token
    for server in servers {
      // Skip servers that don't use HTTP-based transport (OAuth is only for HTTP)
      guard server.transport == .streamableHTTP || server.transport == .sse else { continue }

      // Get the stored token
      guard let storedToken = try? await keychainManager.retrieveStoredToken(for: server.id) else {
        continue
      }

      // Check if token needs refresh
      guard let expiresAt = storedToken.token.expiresAt else { continue }
      let timeUntilExpiration = expiresAt.timeIntervalSinceNow
      if timeUntilExpiration <= refreshBeforeExpiration && storedToken.token.refreshToken != nil {
        logger.info(
          "Token for server \(server.name) expires in \(timeUntilExpiration) seconds, refreshing")

        // Refresh the token
        Task {
          do {
            _ = try await refreshToken(for: server, storedToken: storedToken)
            logger.info("Successfully refreshed token for server \(server.name)")
          } catch {
            logger.error("Failed to refresh token for server \(server.name): \(error)")
          }
        }
      }
    }
  }

  /// Refreshes a token for a server, ensuring only one refresh happens at a time
  func refreshToken(for server: MCPServer, storedToken: StoredOAuthToken) async throws -> OAuthToken
  {
    // Check if there's already an active refresh for this server
    if let activeTask = activeRefreshTasks[server.id] {
      logger.info("Token refresh already in progress for server \(server.name), waiting for result")
      return try await activeTask.value
    }

    // Create a new refresh task
    let refreshTask = Task<OAuthToken, any Error> {
      defer {
        Task {
          self.removeActiveRefreshTask(for: server.id)
        }
      }

      guard let refreshToken = storedToken.token.refreshToken,
        let serverURLString = server.url,
        let serverURL = URL(string: serverURLString)
      else {
        throw MCPClientError.missingRefreshToken
      }

      // Construct the resource metadata URL from the server URL
      let resourceMetadataURL = serverURL.appendingPathComponent(
        ".well-known/oauth-protected-resource")

      // Get the metadata
      let (resourceMetadata, authServerMetadata) = try await oauthClient.discoverMetadata(
        resourceMetadataURL: resourceMetadataURL
      )

      // Perform the refresh
      let newToken = try await oauthClient.refreshToken(
        refreshToken: refreshToken,
        authServerMetadata: authServerMetadata,
        clientID: storedToken.clientID,
        resource: resourceMetadata?.resource
      )

      // Store the new token with the same client ID
      try await storeToken(for: server, token: newToken, clientID: storedToken.clientID)

      return newToken
    }

    // Store the active task
    activeRefreshTasks[server.id] = refreshTask

    return try await refreshTask.value
  }

  private func removeActiveRefreshTask(for serverId: UUID) {
    activeRefreshTasks[serverId] = nil
  }

  deinit {
    refreshTask?.cancel()
  }
}

enum MCPClientError: LocalizedError {
  case missingCommand
  case invalidURL
  case unsupportedTransport(TransportType)
  case missingRefreshToken
  case missingConfiguration(String)

  var errorDescription: String? {
    switch self {
    case .missingCommand:
      return "Server configuration is missing command"
    case .invalidURL:
      return "Server configuration has invalid URL"
    case .unsupportedTransport(let type):
      return "Transport type \(type.rawValue) is not supported"
    case .missingRefreshToken:
      return "No refresh token available"
    case .missingConfiguration(let message):
      return message
    }
  }
}

// MARK: - Dependency Key

extension MCPClientManager: DependencyKey {
  static let liveValue = MCPClientManager()
}

extension DependencyValues {
  var mcpClientManager: MCPClientManager {
    get { self[MCPClientManager.self] }
    set { self[MCPClientManager.self] = newValue }
  }
}
