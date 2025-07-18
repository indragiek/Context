// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Dependencies
import Foundation
import os

@Reducer
struct HTTPConfigFeature {

  @ObservableState
  struct State: Equatable {
    var url: String = ""
    var headers = KeyValueListFeature.State(
      placeholder: KeyValueListFeature.Placeholder(key: "Authorization", value: ""))
    var urlAutoUpdate: Bool = true

    // MCP metadata state
    var mcpMetadata: MCPMetadata?
    var isFetchingMetadata: Bool = false
    var metadataFetchError: String?
    var resolvedEndpointUrl: String?
    var mcpMetadataUrl: String?

    init() {}

    init(from config: HTTPConfig) {
      self.url = config.url
      self.headers = KeyValueListFeature.State(
        items: config.headers.map {
          KeyValueListFeature.Item(key: $0.key, value: $0.value, shouldFocusKey: $0.shouldFocusKey)
        },
        selectedId: config.selectedHeaderId,
        placeholder: KeyValueListFeature.Placeholder(key: "Authorization", value: "")
      )
    }

    var asConfig: HTTPConfig {
      HTTPConfig(
        url: url,
        headers: headers.items.map {
          HeaderItem(key: $0.key, value: $0.value, shouldFocusKey: $0.shouldFocusKey)
        },
        selectedHeaderId: headers.selectedId
      )
    }
  }

  enum Action {
    case urlChanged(String)
    case setURLAutoUpdate(Bool)
    case headers(KeyValueListFeature.Action)

    // MCP metadata actions
    case fetchMetadata
    case metadataFetched(Result<MCPMetadata, any Error>, metadataUrl: String)
    case clearMetadata

    // Internal actions
    case debouncedFetchMetadata
  }

  @Dependency(\.mcpMetadataService) var mcpMetadataService
  private let logger = Logger(subsystem: "com.indragie.Context", category: "HTTPConfigFeature")

  private enum CancelID {
    case fetchMetadata
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.headers, action: \.headers) {
      KeyValueListFeature()
    }

    Reduce { state, action in
      switch action {
      case let .urlChanged(url):
        state.url = url

        // Check if we should fetch metadata
        guard let urlComponents = URLComponents(string: url),
          urlComponents.scheme != nil,
          urlComponents.host != nil
        else {
          // Invalid URL, clear metadata if it exists
          if state.mcpMetadata != nil {
            return .send(.clearMetadata)
          }
          return .none
        }

        // Check if the path is empty or just "/"
        let path = urlComponents.path
        if path.isEmpty || path == "/" {
          // Schedule debounced fetch
          return .concatenate(
            .cancel(id: CancelID.fetchMetadata),
            .run { send in
              try await Task.sleep(for: .milliseconds(500))
              await send(.debouncedFetchMetadata)
            }
            .cancellable(id: CancelID.fetchMetadata)
          )
        } else {
          // User specified a path, clear metadata if it exists
          if state.mcpMetadata != nil {
            return .send(.clearMetadata)
          }
          return .none
        }

      case let .setURLAutoUpdate(enabled):
        state.urlAutoUpdate = enabled
        return .none

      case .headers:
        return .none

      case .debouncedFetchMetadata:
        return .send(.fetchMetadata)

      case .fetchMetadata:
        guard let urlComponents = URLComponents(string: state.url),
          let scheme = urlComponents.scheme,
          let host = urlComponents.host
        else {
          return .none
        }

        // Build the well-known URL
        var wellKnownComponents = URLComponents()
        wellKnownComponents.scheme = scheme
        wellKnownComponents.host = host
        wellKnownComponents.port = urlComponents.port
        wellKnownComponents.path = "/.well-known/mcp.json"

        guard let wellKnownUrl = wellKnownComponents.url else {
          return .none
        }

        state.isFetchingMetadata = true
        state.metadataFetchError = nil

        return .run { send in
          do {
            let metadata = try await mcpMetadataService.fetchMetadata(wellKnownUrl)
            await send(
              .metadataFetched(.success(metadata), metadataUrl: wellKnownUrl.absoluteString))
          } catch {
            // Silent failure as per requirements
            logger.debug("Failed to fetch MCP metadata from \(wellKnownUrl): \(error)")
            await send(.metadataFetched(.failure(error), metadataUrl: wellKnownUrl.absoluteString))
          }
        }

      case let .metadataFetched(result, metadataUrl):
        state.isFetchingMetadata = false

        switch result {
        case let .success(metadata):
          state.mcpMetadata = metadata
          state.resolvedEndpointUrl = metadata.endpoint
          state.mcpMetadataUrl = metadataUrl
          state.metadataFetchError = nil
        case .failure:
          // Silent failure - don't show error to user
          state.mcpMetadata = nil
          state.resolvedEndpointUrl = nil
          state.mcpMetadataUrl = nil
          state.metadataFetchError = nil
        }

        return .none

      case .clearMetadata:
        state.mcpMetadata = nil
        state.resolvedEndpointUrl = nil
        state.mcpMetadataUrl = nil
        state.metadataFetchError = nil
        state.isFetchingMetadata = false
        return .none
      }
    }
  }
}
