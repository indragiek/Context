// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies

// State for individual tool (arguments and responses)
struct ToolState: Sendable {
  var parameterValues: [String: JSONValue] = [:]
  var toolResponse: CallToolResponse.Result?
  var hasLoadedOnce = false
  var rawResponseJSON: JSONValue?
  var rawResponseError: String?
}

// Manual Equatable conformance that excludes toolResponse and raw JSON
extension ToolState: Equatable {
  static func == (lhs: ToolState, rhs: ToolState) -> Bool {
    lhs.parameterValues == rhs.parameterValues && lhs.hasLoadedOnce == rhs.hasLoadedOnce
      && lhs.rawResponseError == rhs.rawResponseError
    // Exclude toolResponse and rawResponseJSON from equality check since they are not Equatable
  }
}

// TCA Dependency
extension DependencyValues {
  var toolCache: LRUCache<String, ToolState> {
    get { self[ToolCacheKey.self] }
    set { self[ToolCacheKey.self] = newValue }
  }
}

private enum ToolCacheKey: DependencyKey {
  static let liveValue = LRUCache<String, ToolState>(maxSize: 25)
  static let testValue = LRUCache<String, ToolState>(maxSize: 25)
}
