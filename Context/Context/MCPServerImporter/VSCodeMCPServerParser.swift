// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import Foundation

enum VSCodeMCPServerParserError: Error, LocalizedError, Equatable {
  case configFileNotFound(path: String)
  case invalidFormat(message: String)
  case userCancelledInput

  var errorDescription: String? {
    switch self {
    case .configFileNotFound(let path):
      return "Configuration file not found at: \(path)"
    case .invalidFormat(let message):
      return "Invalid server configuration: \(message)"
    case .userCancelledInput:
      return "User cancelled input"
    }
  }
}

/// Parses the VSCode MCP server configuration format.
/// This format is different from the Claude Desktop format and supports:
/// - "inputs" field for secure text input
/// - Different server structure under "servers" key
/// - Two different formats: project-scoped (.vscode/mcp.json) and user-scoped (settings.json)
///
/// Example project-scoped configuration (.vscode/mcp.json):
/// {
///   "inputs": [
///     {
///       "type": "promptString",
///       "id": "api-key",
///       "description": "API Key",
///       "password": true
///     }
///   ],
///   "servers": {
///     "perplexity": {
///       "type": "stdio",
///       "command": "docker",
///       "args": ["run", "-i", "--rm"],
///       "env": {
///         "API_KEY": "${input:api-key}"
///       }
///     }
///   }
/// }
///
/// Example user-scoped configuration (settings.json):
/// {
///   "mcp": {
///     "servers": {
///       "my-server": {
///         "type": "stdio",
///         "command": "my-command",
///         "args": []
///       }
///     }
///   }
/// }
struct VSCodeMCPServerParser {
  // Project-scoped configuration format (.vscode/mcp.json)
  struct VSCodeConfiguration: Codable {
    let inputs: [InputDefinition]?
    let servers: [String: ServerDefinition]
  }

  // User-scoped configuration format (settings.json)
  struct VSCodeUserSettings: Codable {
    let mcp: MCPSettings?
  }

  struct MCPSettings: Codable {
    let inputs: [InputDefinition]?
    let servers: [String: ServerDefinition]?
  }

  struct InputDefinition: Codable {
    let type: String
    let id: String
    let description: String
    let password: Bool?
  }

  struct ServerDefinition: Codable {
    let type: String?  // "stdio", "sse", "http" - optional with heuristic fallback
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let url: String?
  }

  static func parseServers(from url: URL, isUserSettings: Bool = false) async throws -> [MCPServer]
  {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw VSCodeMCPServerParserError.configFileNotFound(path: url.path)
    }

    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()

    let inputs: [InputDefinition]
    let servers: [String: ServerDefinition]

    if isUserSettings {
      // Parse as user settings format (settings.json)
      let userSettings = try decoder.decode(VSCodeUserSettings.self, from: data)
      guard let mcp = userSettings.mcp else {
        return []  // No MCP configuration in user settings
      }
      inputs = mcp.inputs ?? []
      servers = mcp.servers ?? [:]
    } else {
      // Parse as project configuration format (.vscode/mcp.json)
      let configuration = try decoder.decode(VSCodeConfiguration.self, from: data)
      inputs = configuration.inputs ?? []
      servers = configuration.servers
    }

    // Collect secure inputs if needed
    let inputValues = try await collectSecureInputs(for: inputs)

    return try convertToMCPServers(servers, inputValues: inputValues)
  }

  private static func collectSecureInputs(for inputs: [InputDefinition]) async throws -> [String:
    String]
  {
    var inputValues: [String: String] = [:]

    for input in inputs {
      guard input.type == "promptString" else {
        continue
      }

      let value = try await promptForSecureInput(
        id: input.id,
        description: input.description,
        isPassword: input.password ?? false
      )

      inputValues[input.id] = value
    }

    return inputValues
  }

  private static func promptForSecureInput(id: String, description: String, isPassword: Bool)
    async throws
    -> String
  {
    let (result, userCancelled) = await showSecureInputAlert(
      id: id, description: description, isPassword: isPassword)

    if userCancelled {
      throw VSCodeMCPServerParserError.userCancelledInput
    }

    guard let value = result, !value.isEmpty else {
      throw VSCodeMCPServerParserError.invalidFormat(
        message: "No value provided for input: \(id)")
    }

    return value
  }

  @MainActor private static func showSecureInputAlert(
    id: String, description: String, isPassword: Bool
  ) -> (
    String?, Bool
  ) {
    let alert = NSAlert()
    alert.messageText = "Visual Studio Code MCP Server Configuration"
    alert.informativeText =
      "The VS Code MCP configuration requires the following input:\n\n\(description)\n\nThis value will be securely substituted into the server's environment variables."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let inputField: NSTextField
    if isPassword {
      inputField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    } else {
      inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    }
    inputField.placeholderString = description

    alert.accessoryView = inputField
    alert.window.initialFirstResponder = inputField

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      return (inputField.stringValue, false)
    } else {
      return (nil, true)
    }
  }

  private static func convertToMCPServers(
    _ definitions: [String: ServerDefinition], inputValues: [String: String]
  ) throws -> [MCPServer] {
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

      // Handle URL-based transports
      if let url = serverDef.url {
        server.url = url
      }

      // Handle environment variables with input substitution
      if let env = serverDef.env {
        server.environment = substituteInputValues(in: env, with: inputValues)
      }

      servers.append(server)
    }

    return servers
  }

  private static func substituteInputValues(
    in environment: [String: String], with inputValues: [String: String]
  ) -> [String: String] {
    var substitutedEnv: [String: String] = [:]

    for (key, value) in environment {
      substitutedEnv[key] = substituteInputPlaceholders(in: value, with: inputValues)
    }

    return substitutedEnv
  }

  private static func substituteInputPlaceholders(
    in value: String, with inputValues: [String: String]
  )
    -> String
  {
    var result = value
    let pattern = #"\$\{input:([^}]+)\}"#

    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
      let matches = regex.matches(
        in: value, options: [], range: NSRange(location: 0, length: value.count))

      // Process matches in reverse order to maintain string indices
      for match in matches.reversed() {
        if let range = Range(match.range, in: value),
          let inputIdRange = Range(match.range(at: 1), in: value)
        {
          let inputId = String(value[inputIdRange])
          if let inputValue = inputValues[inputId] {
            result.replaceSubrange(range, with: inputValue)
          }
        }
      }
    }

    return result
  }

  private static func determineTransport(from serverDef: ServerDefinition) throws -> TransportType {
    // If type is explicitly specified, use it
    if let type = serverDef.type {
      switch type.lowercased() {
      case "stdio":
        return .stdio
      case "sse":
        return .sse
      case "http":
        return .streamableHTTP
      default:
        throw VSCodeMCPServerParserError.invalidFormat(
          message: "Unknown transport type: \(type)")
      }
    }

    // Apply heuristic if type is not specified
    if let url = serverDef.url {
      if url.hasSuffix("/sse") {
        return .sse
      } else {
        // Default to HTTP for any URL (including those ending with "/mcp")
        return .streamableHTTP
      }
    } else {
      // No URL specified, default to stdio
      return .stdio
    }
  }
}
