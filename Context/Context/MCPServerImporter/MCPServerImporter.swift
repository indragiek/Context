// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

protocol MCPServerImporter {
  static var identifier: String { get }
  static var name: String { get }
  static var bundleIdentifiers: [String] { get }

  init()

  static func configurationFileURLs(projectDirectoryURLs: [URL]) -> [URL]
  func importServers(projectDirectoryURLs: [URL]) async throws -> [MCPServer]
}
