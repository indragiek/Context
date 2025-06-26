// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore

struct SchemaNode: Identifiable {
  let id: String
  let key: String
  let schema: JSONValue
  let isRequired: Bool
  let level: Int
  let path: [String]
  var isArrayItem: Bool = false
  var arrayIndex: Int? = nil

  var displayName: String {
    isArrayItem ? "[\(arrayIndex ?? 0)]" : key
  }

  var hasChildren: Bool {
    guard let type = extractType(from: schema) else { return false }
    return type == "object" || type == "array"
  }

  private func extractType(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let typeStr) = obj["type"]
    {
      return typeStr
    }
    return nil
  }
}
