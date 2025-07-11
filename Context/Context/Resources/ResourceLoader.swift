// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation

struct LoadedResource: Equatable {
  let embeddedResources: [EmbeddedResource]
  let rawResponseJSON: JSONValue?
  let requestError: (any Error)?

  static func == (lhs: LoadedResource, rhs: LoadedResource) -> Bool {
    lhs.embeddedResources == rhs.embeddedResources
      && (lhs.requestError != nil) == (rhs.requestError != nil)
    // Note: rawResponseJSON is not compared because JSONValue is not Equatable
  }
}

@DependencyClient
struct ResourceLoader {
  var loadResource: @Sendable (String, MCPServer) async -> LoadedResource = { _, _ in
    LoadedResource(embeddedResources: [], rawResponseJSON: nil, requestError: nil)
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

        // Encode the raw response and then decode to JSONValue
        let jsonData = try encoder.encode(responseToEncode)
        let jsonValue = try JSONDecoder().decode(JSONValue.self, from: jsonData)

        return LoadedResource(
          embeddedResources: contents,
          rawResponseJSON: jsonValue,
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

        // Try to create JSON representation of the error
        var jsonValue: JSONValue? = nil
        
        if let clientError = error as? ClientError {
          switch clientError {
          case .requestFailed(_, let jsonRPCError):
            // Encode the JSON-RPC error
            if let jsonData = try? encoder.encode(jsonRPCError) {
              jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData)
            }
          default:
            break
          }
        }
        
        // If we couldn't create a specific error JSON, create a generic one
        if jsonValue == nil {
          let errorResponse = ErrorResponse(
            error: ErrorResponse.ErrorInfo(
              code: -32603,
              message: error.localizedDescription
            )
          )
          
          if let jsonData = try? encoder.encode(errorResponse) {
            jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData)
          }
        }

        return LoadedResource(
          embeddedResources: [],
          rawResponseJSON: jsonValue,
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
