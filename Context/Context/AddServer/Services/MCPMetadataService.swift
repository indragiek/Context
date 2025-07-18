// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Dependencies
import Foundation
import os

private let logger = Logger(subsystem: "com.indragie.Context", category: "MCPMetadataService")

struct MCPMetadataService {
  var fetchMetadata: @Sendable (_ url: URL) async throws -> MCPMetadata
}

extension MCPMetadataService: DependencyKey {
  static var liveValue: MCPMetadataService {
    MCPMetadataService(
      fetchMetadata: { url in
        logger.debug("Fetching MCP metadata from: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
          throw MCPMetadataError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
          throw MCPMetadataError.httpError(statusCode: httpResponse.statusCode)
        }

        let metadata = try JSONDecoder().decode(MCPMetadata.self, from: data)
        logger.debug("Successfully fetched MCP metadata: \(String(describing: metadata.name))")

        return metadata
      }
    )
  }

  static var testValue: MCPMetadataService {
    MCPMetadataService(
      fetchMetadata: { _ in
        MCPMetadata(
          name: "Test Server",
          description: "Test Description",
          icon: "https://example.com/icon.png",
          endpoint: "https://example.com/mcp"
        )
      }
    )
  }
}

extension DependencyValues {
  var mcpMetadataService: MCPMetadataService {
    get { self[MCPMetadataService.self] }
    set { self[MCPMetadataService.self] = newValue }
  }
}

enum MCPMetadataError: LocalizedError {
  case invalidResponse
  case httpError(statusCode: Int)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid response from server"
    case .httpError(let statusCode):
      return "HTTP error: \(statusCode)"
    }
  }
}
