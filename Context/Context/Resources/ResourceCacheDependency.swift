// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies

struct ResourceCacheState: Sendable {
  var variableValues: [String: String] = [:]
  var embeddedResources: [EmbeddedResource] = []
  var hasLoadedOnce: Bool = false
  var lastFetchedURI: String? = nil
  var viewMode: ResourceViewMode = .preview
  var rawResponseJSON: String? = nil
  var rawResponseError: String? = nil
}

// Manual Equatable implementation to handle non-Equatable types
extension ResourceCacheState: Equatable {
  static func == (lhs: ResourceCacheState, rhs: ResourceCacheState) -> Bool {
    // Compare properties that are Equatable
    guard lhs.variableValues == rhs.variableValues &&
          lhs.hasLoadedOnce == rhs.hasLoadedOnce &&
          lhs.lastFetchedURI == rhs.lastFetchedURI &&
          lhs.viewMode == rhs.viewMode &&
          lhs.rawResponseJSON == rhs.rawResponseJSON &&
          lhs.rawResponseError == rhs.rawResponseError else {
      return false
    }
    
    // For non-Equatable types, compare counts as a proxy
    return lhs.embeddedResources.count == rhs.embeddedResources.count
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
