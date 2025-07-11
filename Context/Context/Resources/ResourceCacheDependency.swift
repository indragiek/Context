// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation

struct ResourceCacheState: Sendable {
  var variableValues: [String: String] = [:]
  var embeddedResources: [EmbeddedResource] = []
  var hasLoadedOnce: Bool = false
  var lastFetchedURI: String? = nil
  var responseJSON: JSONValue? = nil
  var responseError: (any Error)? = nil
}

// Manual Equatable implementation to handle non-Equatable types
extension ResourceCacheState: Equatable {
  static func == (lhs: ResourceCacheState, rhs: ResourceCacheState) -> Bool {
    // Compare all Equatable properties
    guard
      lhs.variableValues == rhs.variableValues && lhs.embeddedResources == rhs.embeddedResources
        && lhs.hasLoadedOnce == rhs.hasLoadedOnce && lhs.lastFetchedURI == rhs.lastFetchedURI
        && lhs.responseJSON == rhs.responseJSON
    else {
      return false
    }

    // For errors, compare both existence and type
    let lhsErrorType = lhs.responseError.map { type(of: $0) }
    let rhsErrorType = rhs.responseError.map { type(of: $0) }
    let lhsErrorMessage = lhs.responseError?.localizedDescription
    let rhsErrorMessage = rhs.responseError?.localizedDescription

    return lhsErrorType == rhsErrorType && lhsErrorMessage == rhsErrorMessage
  }
}

// TCA Dependency
extension DependencyValues {
  var resourceCache: LRUCache<String, ResourceCacheState> {
    get { self[ResourceCacheKey.self] }
    set { self[ResourceCacheKey.self] = newValue }
  }
}

private enum ResourceCacheKey: DependencyKey {
  static let liveValue = LRUCache<String, ResourceCacheState>(maxSize: 25)
  static let testValue = LRUCache<String, ResourceCacheState>(maxSize: 25)
}
