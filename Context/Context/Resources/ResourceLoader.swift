// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation

struct LoadedResource: Equatable {
  let embeddedResources: [EmbeddedResource]
  let rawResponseJSON: String
  let requestError: (any Error)?

  static func == (lhs: LoadedResource, rhs: LoadedResource) -> Bool {
    lhs.embeddedResources == rhs.embeddedResources
      && lhs.rawResponseJSON == rhs.rawResponseJSON
      && (lhs.requestError != nil) == (rhs.requestError != nil)
  }
}

@DependencyClient
struct ResourceLoader {
  var loadResource: @Sendable (String, MCPServer) async -> LoadedResource = { _, _ in
    LoadedResource(embeddedResources: [], rawResponseJSON: "null", requestError: nil)
  }
}

extension ResourceLoader: DependencyKey {
  static let liveValue = ResourceLoader(
    loadResource: { uri, server in
      @Dependency(\.mcpClientManager) var mcpClientManager

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

      do {
        // Get the client and read the resource
        let client = try await mcpClientManager.client(for: server)
        let contents = try await client.readResource(uri: uri)

        // Create the response structure for raw view
        // Encode contents directly as the Result would contain just this
        let responseToEncode = ["contents": contents]

        // Encode the raw response
        let jsonData = try encoder.encode(responseToEncode)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "null"

        return LoadedResource(
          embeddedResources: contents,
          rawResponseJSON: jsonString,
          requestError: nil
        )
      } catch {
        // Create error response for raw view
        struct ErrorResponse: Encodable {
          struct ErrorInfo: Encodable {
            let code: Int
            let message: String
          }
          let error: ErrorInfo
        }

        let errorResponse = ErrorResponse(
          error: ErrorResponse.ErrorInfo(
            code: -32603,
            message: error.localizedDescription
          )
        )

        let jsonData = try? encoder.encode(errorResponse)
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "null"

        return LoadedResource(
          embeddedResources: [],
          rawResponseJSON: jsonString,
          requestError: error
        )
      }
    }
  )
}

extension DependencyValues {
  var resourceLoader: ResourceLoader {
    get { self[ResourceLoader.self] }
    set { self[ResourceLoader.self] = newValue }
  }
}
