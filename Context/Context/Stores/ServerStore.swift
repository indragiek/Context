// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation
import GRDB
import SharingGRDB
import os

// MARK: - Validation Types

enum ServerNameValidationResult: Equatable {
  case valid
  case invalid(reason: String)
}

// MARK: - Server Store Protocol

protocol ServerStoreProtocol: Sendable {
  /// Creates a new server in the database
  func createServer(_ server: MCPServer) async throws

  /// Updates an existing server in the database
  func updateServer(_ server: MCPServer) async throws

  /// Deletes a server and all associated resources
  func deleteServer(_ server: MCPServer) async throws

  /// Finds a server by name and transport type
  func findServer(name: String, transport: TransportType) async throws -> MCPServer?

  /// Builds an MCPServer from configuration
  func buildServer(
    id: UUID,
    name: String,
    transport: TransportType,
    config: TransportConfig
  ) -> MCPServer

  /// Validates a server name for filesystem compatibility and uniqueness
  func validateServerName(
    _ name: String,
    excludingServerID: UUID?
  ) async throws -> ServerNameValidationResult
}

// MARK: - Server Store Implementation

struct ServerStore: ServerStoreProtocol {
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.mcpClientManager) var mcpClientManager
  @Dependency(\.dxtConfigKeychain) var dxtConfigKeychain
  @Dependency(\.dxtStore) var dxtStore

  private let logger = Logger(subsystem: "com.indragie.Context", category: "ServerStore")

  func createServer(_ server: MCPServer) async throws {
    try await database.write { db in
      try MCPServer.insert { server }.execute(db)
    }
    logger.info("Successfully created server: \(server.name)")
  }

  func updateServer(_ server: MCPServer) async throws {
    try await database.write { db in
      try MCPServer.update(server).execute(db)
    }
    logger.info("Successfully updated server: \(server.name)")
  }

  func deleteServer(_ server: MCPServer) async throws {
    // Disconnect the server first
    try? await mcpClientManager.disconnect(server: server)

    // Delete OAuth token if any
    do {
      try await mcpClientManager.deleteToken(for: server)
      logger.info("Deleted OAuth token for server \(server.name)")
    } catch {
      logger.warning("Failed to delete OAuth token for server \(server.name): \(error)")
    }

    // Delete DXT keychain values if it's a DXT server
    if server.transport == .dxt, let userConfig = server.dxtUserConfig {
      for (_, value) in userConfig.values {
        if case .keychainReference(let uuid) = value.value {
          do {
            try await dxtConfigKeychain.deleteValue(for: uuid)
            logger.info("Deleted keychain value for DXT server config")
          } catch {
            logger.warning("Failed to delete keychain value: \(error)")
          }
        }
      }
    }

    // Delete from database
    try await database.write { db in
      try MCPServer.delete().where { $0.id == server.id }.execute(db)
    }

    // Clean up DXT installation directory if it's a DXT server
    if server.transport == .dxt,
      let urlString = server.url,
      let url = URL(string: urlString)
    {
      do {
        try FileManager.default.removeItem(at: url)
        logger.info("Removed DXT installation directory: \(url.path)")
      } catch {
        logger.warning("Failed to remove DXT installation directory: \(error)")
      }
    }

    logger.info("Successfully deleted server: \(server.name)")
  }

  func findServer(name: String, transport: TransportType) async throws -> MCPServer? {
    try await database.read { db in
      try MCPServer
        .where { $0.name == name && $0.transport == transport }
        .fetchOne(db)
    }
  }

  func buildServer(
    id: UUID,
    name: String,
    transport: TransportType,
    config: TransportConfig
  ) -> MCPServer {
    // Always use streamableHTTP instead of deprecated .sse
    let finalTransport =
      (transport == .streamableHTTP || transport == .sse) ? .streamableHTTP : transport

    var server = MCPServer(
      id: id,
      name: name,
      transport: finalTransport
    )

    switch (transport, config) {
    case (.stdio, .stdio(let stdioConfig)):
      server.command = stdioConfig.command
      let filteredArgs = stdioConfig.arguments.map { $0.value }.filter { !$0.isEmpty }
      server.args = filteredArgs.isEmpty ? nil : filteredArgs
      let validEnv = stdioConfig.environmentVariables.filter {
        !$0.name.isEmpty && !$0.value.isEmpty
      }
      var envDict: [String: String] = [:]
      for envVar in validEnv {
        envDict[envVar.name] = envVar.value
      }
      server.environment = envDict.isEmpty ? nil : envDict

    case (.sse, .http(let httpConfig)), (.streamableHTTP, .http(let httpConfig)):
      server.url = httpConfig.url
      let validHeaders = httpConfig.headers.filter { !$0.key.isEmpty && !$0.value.isEmpty }
      var headerDict: [String: String] = [:]
      for header in validHeaders {
        headerDict[header.key] = header.value
      }
      server.headers = headerDict.isEmpty ? nil : headerDict

    case (.dxt, .dxt(let dxtConfig)):
      // For DXT, set the URL to the installed location using the server ID
      if dxtConfig.manifest != nil {
        do {
          let serverDir = try dxtStore.serverDirectory(for: id)
          server.url = serverDir.absoluteString
        } catch {
          logger.error("Failed to generate server directory URL for DXT server \(id): \(error)")
          // Return a server without URL which will fail validation
          // This is better than silently continuing with an invalid server
        }

        // Set user config if it has values
        if !dxtConfig.userConfig.values.isEmpty {
          server.dxtUserConfig = dxtConfig.userConfig
        }
      }

    default:
      break  // Mismatched transport and config
    }

    return server
  }

  func validateServerName(
    _ name: String,
    excludingServerID: UUID? = nil
  ) async throws -> ServerNameValidationResult {
    // Check if name is empty
    guard !name.isEmpty else {
      return .invalid(reason: "Server name cannot be empty")
    }

    // Check for invalid file path characters
    let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
    if name.rangeOfCharacter(from: invalidCharacters) != nil {
      return .invalid(reason: "Server name cannot contain: / \\ : * ? \" < > |")
    }

    // Check for reserved filenames on macOS/Unix
    let reservedNames = [".", "..", "~"]
    if reservedNames.contains(name.lowercased()) {
      return .invalid(reason: "'\(name)' is a reserved name and cannot be used")
    }

    // Check for names that start/end with spaces or dots (problematic for filesystems)
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    if trimmed != name {
      return .invalid(reason: "Server name cannot start or end with spaces")
    }

    if name.hasPrefix(".") || name.hasSuffix(".") {
      return .invalid(reason: "Server name cannot start or end with a period")
    }

    // Check for control characters
    if name.rangeOfCharacter(from: .controlCharacters) != nil {
      return .invalid(reason: "Server name cannot contain control characters")
    }

    // Check for duplicate names (case-insensitive)
    let lowercasedName = name.lowercased()
    let existingServers = try await database.read { db in
      try MCPServer.all.fetchAll(db)
    }

    for server in existingServers {
      // Skip the server being edited
      if let excludingID = excludingServerID, server.id == excludingID {
        continue
      }

      // Case-insensitive comparison
      if server.name.lowercased() == lowercasedName {
        return .invalid(reason: "A server with this name already exists")
      }
    }

    return .valid
  }
}

// MARK: - Dependency Registration

private enum ServerStoreKey: DependencyKey {
  static let liveValue: any ServerStoreProtocol = ServerStore()
}

extension DependencyValues {
  var serverStore: any ServerStoreProtocol {
    get { self[ServerStoreKey.self] }
    set { self[ServerStoreKey.self] = newValue }
  }
}
