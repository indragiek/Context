// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

enum ClaudeMCPServerParserError: Error, LocalizedError, Equatable {
  case configFileNotFound(path: String)
  case invalidFormat(message: String)

  var errorDescription: String? {
    switch self {
    case .configFileNotFound(let path):
      return "Configuration file not found at: \(path)"
    case .invalidFormat(let message):
      return "Invalid server configuration: \(message)"
    }
  }
}

/// This parses the MCP server configuration file format originally implemented
/// by Claude Desktop, which is also now supported by Claude Code, Cursor, Windsurf,
/// and other products. An example configuration looks like this:
///
/// {
///   "mcpServers": {
///   "memory": {
///     "command": "npx",
///     "args": ["-y", "@modelcontextprotocol/server-memory"]
///    },
///    "filesystem": {
///      "command": "npx",
///      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed/files"]
///    },
///    "github": {
///      "command": "npx",
///      "args": ["-y", "@modelcontextprotocol/server-github"],
///      "env": {
///        "GITHUB_PERSONAL_ACCESS_TOKEN": "<YOUR_TOKEN>"
///      }
///    }
///  }
///}
struct ClaudeMCPServerParser {
  struct ServerConfiguration: Codable {
    let mcpServers: [String: ServerDefinition]
  }

  struct ServerDefinition: Codable {
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let url: String?
  }

  static func parseServers(from url: URL) throws -> [MCPServer] {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw ClaudeMCPServerParserError.configFileNotFound(path: url.path)
    }

    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    let configuration = try decoder.decode(ServerConfiguration.self, from: data)

    return try convertToMCPServers(configuration.mcpServers)
  }

  private static func convertToMCPServers(_ definitions: [String: ServerDefinition]) throws
    -> [MCPServer]
  {
    var servers: [MCPServer] = []

    for (serverName, serverDef) in definitions {
      let transport = try determineTransport(from: serverDef)

      var server = MCPServer(
        id: UUID(),
        name: serverName,
        transport: transport
      )

      // Handle stdio transport
      if let command = serverDef.command {
        server.command = command
        server.args = serverDef.args
      }

      // Handle URL-based transports (SSE or Streamable HTTP)
      if let url = serverDef.url {
        server.url = url
      }

      // Handle environment variables
      server.environment = serverDef.env

      servers.append(server)
    }

    return servers
  }

  private static func determineTransport(from serverDef: ServerDefinition) throws -> TransportType {
    // If there's a command key, it's stdio transport
    if serverDef.command != nil {
      return .stdio
    }

    // If there's a URL key, determine if it's SSE or Streamable HTTP
    if let urlString = serverDef.url {
      if urlString.hasSuffix("/sse") {
        return .sse
      } else if urlString.hasSuffix("/mcp") {
        return .streamableHTTP
      } else {
        // Default to Streamable HTTP as per instructions
        return .streamableHTTP
      }
    }

    throw ClaudeMCPServerParserError.invalidFormat(
      message: "Server must have either 'command' or 'url' key")
  }
}
