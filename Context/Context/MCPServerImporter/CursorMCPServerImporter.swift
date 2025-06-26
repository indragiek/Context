// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

struct CursorMCPServerImporter: MCPServerImporter {
  static let identifier = "cursor"
  static let name = "Cursor"
  static let bundleIdentifiers = ["com.todesktop.230313mzl4w4u92"]

  static func configurationFileURLs(projectDirectoryURLs: [URL]) -> [URL] {
    guard let homeURL = getUserHomeDirectoryURLFromPasswd() else { return [] }
    let userScopedConfigURL = homeURL.appendingPathComponent(".cursor/mcp.json")

    var urls = [userScopedConfigURL]

    for projectURL in projectDirectoryURLs {
      let projectConfigURL = projectURL.appendingPathComponent(".cursor").appendingPathComponent(
        "mcp.json")
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
