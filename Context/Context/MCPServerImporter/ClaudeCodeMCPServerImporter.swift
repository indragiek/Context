// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

struct ClaudeCodeMCPServerImporter: MCPServerImporter {
  static let identifier = "claude-code"
  static let name = "Claude Code"
  static let bundleIdentifiers: [String] = []

  static func configurationFileURLs(projectDirectoryURLs: [URL]) -> [URL] {
    var urls: [URL] = []

    // User-scoped configuration in ~/.claude.json
    guard let homeURL = getUserHomeDirectoryURLFromPasswd() else { return [] }
    let userConfigURL = homeURL.appendingPathComponent(".claude.json")
    urls.append(userConfigURL)

    // Project-scoped configurations (.mcp.json in project root)
    for projectURL in projectDirectoryURLs {
      let projectConfigURL = projectURL.appendingPathComponent(".mcp.json")
      urls.append(projectConfigURL)
    }

    return urls
  }

  func importServers(projectDirectoryURLs: [URL]) async throws -> [MCPServer] {
    let configURLs = Self.configurationFileURLs(projectDirectoryURLs: projectDirectoryURLs)
    var allServers: [MCPServer] = []

    for configURL in configURLs {
      // Skip if file doesn't exist
      guard FileManager.default.fileExists(atPath: configURL.path) else {
        continue
      }

      let servers = try ClaudeMCPServerParser.parseServers(from: configURL)
      allServers.append(contentsOf: servers)
    }

    return allServers
  }
}
