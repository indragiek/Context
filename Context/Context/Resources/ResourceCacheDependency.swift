// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies

struct ResourceCacheState: Equatable, Sendable {
  var variableValues: [String: String] = [:]
  var embeddedResources: [EmbeddedResource] = []
  var hasLoadedOnce: Bool = false
  var lastFetchedURI: String? = nil
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
