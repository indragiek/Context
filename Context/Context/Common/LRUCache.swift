/// A generic thread-safe LRU (Least Recently Used) cache implementation.
///
/// This cache maintains a fixed maximum size and evicts the least recently used items
/// when the cache reaches capacity.
actor LRUCache<Key: Hashable & Sendable, Value: Sendable> {
  private let maxSize: Int
  private var cache: [Key: Value] = [:]
  private var accessOrder: [Key] = []

  init(maxSize: Int = 25) {
    self.maxSize = maxSize
  }

  func get(for key: Key) -> Value? {
    if let value = cache[key] {
      if let index = accessOrder.firstIndex(of: key) {
        accessOrder.remove(at: index)
      }
      accessOrder.append(key)
      return value
    }
    return nil
  }

  func set(_ value: Value, for key: Key) {
    if let index = accessOrder.firstIndex(of: key) {
      accessOrder.remove(at: index)
    }

    cache[key] = value
    accessOrder.append(key)

    while accessOrder.count > maxSize {
      let oldestKey = accessOrder.removeFirst()
      cache.removeValue(forKey: oldestKey)
    }
  }

  func getAll() -> [Key: Value] {
    return cache
  }

  func clear() {
    cache.removeAll()
    accessOrder.removeAll()
  }
}
