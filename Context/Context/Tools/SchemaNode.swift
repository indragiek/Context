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
  var isDynamic: Bool = false  // Whether this is a dynamic property (can have type selector)
  var dynamicType: String? = nil  // For dynamic properties, store the selected type

  var displayName: String {
    if isArrayItem {
      return "[\(arrayIndex ?? 0)]"
    } else {
      // Use title if available, otherwise use key
      if let title = extractTitle(from: schema) {
        return title
      }
      return key
    }
  }

  var hasChildren: Bool {
    // For dynamic properties, check the dynamic type first
    let effectiveType = dynamicType ?? extractType(from: schema)
    guard let type = effectiveType else { return false }
    return type == "object" || type == "array"
  }
  
  func hasChildrenWithValue(_ value: JSONValue) -> Bool {
    // For dynamic properties, check the dynamic type first
    let effectiveType = dynamicType ?? extractType(from: schema)
    guard let type = effectiveType else { return false }
    
    switch type {
    case "object":
      return true // Objects can always have children (even if empty)
    case "array":
      // Arrays should show disclosure if they have items or if they're arrays by type
      if case .array(let arr) = value, !arr.isEmpty {
        return true
      }
      return type == "array" // Show disclosure for array types even if empty
    default:
      return false
    }
  }

  private func extractType(from schema: JSONValue) -> String? {
    // Handle boolean schemas
    if case .boolean(let bool) = schema {
      return bool ? nil : "never"
    }
    
    if case .object(let obj) = schema,
      case .string(let typeStr) = obj["type"]
    {
      return typeStr
    }
    return nil
  }
  
  private func extractTitle(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
       case .string(let title) = obj["title"] {
      return title
    }
    return nil
  }
}
