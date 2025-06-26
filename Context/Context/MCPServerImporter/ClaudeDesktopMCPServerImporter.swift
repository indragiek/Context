// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

struct ClaudeDesktopMCPServerImporter: MCPServerImporter {
  static let identifier = "claude-desktop"
  static let name = "Claude Desktop"
  static let bundleIdentifiers = ["com.anthropic.claudefordesktop"]

  static func configurationFileURLs(projectDirectoryURLs: [URL]) -> [URL] {
    guard let homeURL = getUserHomeDirectoryURLFromPasswd() else { return [] }
    return [
      homeURL.appendingPathComponent(
        "Library/Application Support/Claude/claude_desktop_config.json")
    ]
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
