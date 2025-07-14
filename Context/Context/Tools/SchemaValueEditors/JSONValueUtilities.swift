// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation

enum JSONValueUtilities {
  static func jsonValuesEqual(_ a: JSONValue, _ b: JSONValue) -> Bool {
    switch (a, b) {
    case (.null, .null):
      return true
    case (.boolean(let a), .boolean(let b)):
      return a == b
    case (.string(let a), .string(let b)):
      return a == b
    case (.number(let a), .number(let b)):
      return a == b
    case (.integer(let a), .integer(let b)):
      return a == b
    case (.array(let a), .array(let b)):
      return a.count == b.count && zip(a, b).allSatisfy(jsonValuesEqual)
    case (.object(let a), .object(let b)):
      return a.keys == b.keys && a.keys.allSatisfy { jsonValuesEqual(a[$0]!, b[$0]!) }
    default:
      return false
    }
  }
  
  static func matchesType(_ value: JSONValue, _ type: String) -> Bool {
    switch (value, type) {
    case (.null, "null"):
      return true
    case (.boolean, "boolean"):
      return true
    case (.string, "string"):
      return true
    case (.number, "number"):
      return true
    case (.integer, "integer"):
      return true
    case (.integer, "number"):
      return true // integers are also numbers
    case (.array, "array"):
      return true
    case (.object, "object"):
      return true
    default:
      return false
    }
  }
  
  static func jsonValueToString(_ value: JSONValue) -> String {
    switch value {
    case .null:
      return "null"
    case .boolean(let bool):
      return bool ? "true" : "false"
    case .string(let str):
      return str
    case .number(let num):
      return String(num)
    case .integer(let int):
      return String(int)
    case .array:
      return "[Array]"
    case .object:
      return "{Object}"
    }
  }
  
  static func parseValue(_ string: String) -> JSONValue {
    if string.isEmpty || string == "null" {
      return .null
    } else if string == "true" {
      return .boolean(true)
    } else if string == "false" {
      return .boolean(false)
    } else if let int = Int64(string) {
      return .integer(int)
    } else if let num = Double(string) {
      return .number(num)
    } else {
      return .string(string)
    }
  }
}