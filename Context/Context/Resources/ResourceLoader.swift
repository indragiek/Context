// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation

#if !SENTRY_DISABLED
import Sentry
#endif

struct LoadedResource: Equatable {
  let embeddedResources: [EmbeddedResource]
  let responseJSON: JSONValue?
  let responseError: (any Error)?

  static func == (lhs: LoadedResource, rhs: LoadedResource) -> Bool {
    // Compare Equatable properties
    guard lhs.embeddedResources == rhs.embeddedResources &&
          lhs.responseJSON == rhs.responseJSON else {
      return false
    }
    
    // Compare errors by their existence and type
    let lhsErrorType = lhs.responseError.map { type(of: $0) }
    let rhsErrorType = rhs.responseError.map { type(of: $0) }
    let lhsErrorMessage = lhs.responseError?.localizedDescription
    let rhsErrorMessage = rhs.responseError?.localizedDescription
    
    return lhsErrorType == rhsErrorType && lhsErrorMessage == rhsErrorMessage
  }
}

@DependencyClient
struct ResourceLoader {
  var loadResource: @Sendable (String, MCPServer) async -> LoadedResource = { _, _ in
    LoadedResource(embeddedResources: [], responseJSON: nil, responseError: nil)
  }
}

extension ResourceLoader: DependencyKey {
  static let liveValue = ResourceLoader(
    loadResource: { uri, server in
      @Dependency(\.mcpClientManager) var mcpClientManager

      #if !SENTRY_DISABLED
      let span = SentrySDK.span?.startChild(operation: "resource.load_content") ?? SentrySDK.startTransaction(
        name: "resource.load_content",
        operation: "task"
      )
      span.setData(value: uri, key: "resource_uri")
      #endif

      do {
        // Get the client and read the resource
        let client = try await mcpClientManager.client(for: server)
        let contents = try await client.readResource(uri: uri)

        // Create the response structure for raw view
        // Encode contents directly as the Result would contain just this
        let responseToEncode = ["contents": contents]

        // Encode the raw response and then decode to JSONValue
        let jsonData = try JSONUtility.prettyData(from: responseToEncode, escapeSlashes: true)
        let jsonValue = try JSONDecoder().decode(JSONValue.self, from: jsonData)

        #if !SENTRY_DISABLED
        span.setData(value: jsonData.count, key: "resource_size")
        span.setData(value: false, key: "is_cached") // Live value is never cached
        if let firstContent = contents.first {
          span.setData(value: firstContent.mimeType, key: "mime_type")
        }
        span.finish()
        #endif

        return LoadedResource(
          embeddedResources: contents,
          responseJSON: jsonValue,
          responseError: nil
        )
      } catch {
        #if !SENTRY_DISABLED
        span.finish(status: .internalError)
        #endif
        
        return LoadedResource(
          embeddedResources: [],
          responseJSON: nil,
          responseError: error
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
