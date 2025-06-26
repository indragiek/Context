// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

struct VSCodeMCPServerImporter: MCPServerImporter {
  static let identifier = "vscode"
  static let name = "Visual Studio Code"
  static let bundleIdentifiers = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]

  static func configurationFileURLs(projectDirectoryURLs: [URL]) -> [URL] {
    var urls: [URL] = []

    // User-scoped configuration (settings.json)
    if let homeURL = getUserHomeDirectoryURLFromPasswd() {
      let userSettingsURL = homeURL.appendingPathComponent(
        "Library/Application Support/Code/User/settings.json")
      urls.append(userSettingsURL)
    }

    // Project-scoped configurations (.vscode/mcp.json in project root)
    for projectURL in projectDirectoryURLs {
      let vscodeDirURL = projectURL.appendingPathComponent(".vscode")
      let projectConfigURL = vscodeDirURL.appendingPathComponent("mcp.json")
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

      // Determine if this is user settings based on the path
      let isUserSettings = configURL.path.contains("User/settings.json")
      let servers = try await VSCodeMCPServerParser.parseServers(
        from: configURL, isUserSettings: isUserSettings)
      allServers.append(contentsOf: servers)
    }

    return allServers
  }
}
