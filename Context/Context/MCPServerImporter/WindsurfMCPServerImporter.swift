// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

struct WindsurfMCPServerImporter: MCPServerImporter {
  static let identifier = "windsurf"
  static let name = "Windsurf"
  static let bundleIdentifiers = ["com.exafunction.windsurf"]

  static func configurationFileURLs(projectDirectoryURLs: [URL]) -> [URL] {
    guard let homeURL = getUserHomeDirectoryURLFromPasswd() else { return [] }
    let userScopedConfigURL = homeURL.appendingPathComponent(".codeium/windsurf/mcp_config.json")

    // Windsurf only uses user-scoped configuration
    return [userScopedConfigURL]
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
