// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies

// TCA Dependency
extension DependencyValues {
  var promptCache: LRUCache<String, PromptState> {
    get { self[PromptCacheKey.self] }
    set { self[PromptCacheKey.self] = newValue }
  }
}

private enum PromptCacheKey: DependencyKey {
  static let liveValue = LRUCache<String, PromptState>(maxSize: 25)
  static let testValue = LRUCache<String, PromptState>(maxSize: 25)
}
