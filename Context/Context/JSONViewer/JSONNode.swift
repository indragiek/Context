// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore

struct JSONNode: Identifiable, Hashable {
  let id: String
  let key: String?
  let value: JSONValue
  let keyPath: String
  let level: Int

  init(key: String?, value: JSONValue, keyPath: String, level: Int) {
    self.key = key
    self.value = value
    self.keyPath = keyPath
    self.level = level
    self.id = keyPath.isEmpty ? "root" : keyPath
  }

  func children(expandedNodes: Set<String>) -> [JSONNode]? {
    guard expandedNodes.contains(id) else { return nil }

    switch value {
    case .object(let dict):
      return dict.keys.sorted().map { key in
        JSONNode(
          key: key,
          value: dict[key]!,
          keyPath: keyPath.isEmpty ? key : "\(keyPath).\(key)",
          level: level + 1
        )
      }
    case .array(let array):
      return array.enumerated().map { index, value in
        JSONNode(
          key: "\(index)",
          value: value,
          keyPath: keyPath.isEmpty ? "\(index)" : "\(keyPath)[\(index)]",
          level: level + 1
        )
      }
    default:
      return nil
    }
  }

  var hasChildren: Bool {
    switch value {
    case .object(let dict):
      return !dict.isEmpty
    case .array(let array):
      return !array.isEmpty
    default:
      return false
    }
  }

  var isContainer: Bool {
    switch value {
    case .object(_), .array(_):
      return true
    default:
      return false
    }
  }
}
