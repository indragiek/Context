// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation

enum SchemaValueHelpers {
  static func extractType(from schema: JSONValue, currentValue: JSONValue = .null) -> String? {
    // Handle boolean schemas
    if case .boolean(let bool) = schema {
      // Boolean schemas don't have a specific type
      // true allows any type, false allows no type
      return bool ? nil : "never"
    }
    
    if case .object(let obj) = schema,
       let typeValue = obj["type"] {
      if case .string(let typeStr) = typeValue {
        return typeStr
      } else if case .array(let types) = typeValue {
        // For multiple types, determine the primary type based on current value
        // or use the first non-null type
        return determinePrimaryType(from: types, currentValue: currentValue)
      }
    }
    return nil
  }
  
  static func extractTypes(from schema: JSONValue) -> [String]? {
    // Handle boolean schemas
    if case .boolean(let bool) = schema {
      // true allows all types, false allows none
      return bool ? nil : []
    }
    
    if case .object(let obj) = schema,
       let typeValue = obj["type"] {
      if case .string(let typeStr) = typeValue {
        return [typeStr]
      } else if case .array(let types) = typeValue {
        return types.compactMap { 
          if case .string(let str) = $0 { return str }
          return nil
        }
      }
    }
    return nil
  }
  
  static func determinePrimaryType(from types: [JSONValue], currentValue: JSONValue) -> String? {
    // First check if current value matches any of the types
    for type in types {
      if case .string(let typeStr) = type {
        if JSONValueUtilities.matchesType(currentValue, typeStr) && typeStr != "null" {
          return typeStr
        }
      }
    }
    
    // If no match or value is null, return first non-null type
    for type in types {
      if case .string(let typeStr) = type, typeStr != "null" {
        return typeStr
      }
    }
    
    // If only null type, return null
    return "null"
  }
  
  static func extractEnum(from schema: JSONValue) -> [JSONValue]? {
    if case .object(let obj) = schema,
       case .array(let enumValues) = obj["enum"] {
      return enumValues
    }
    return nil
  }
  
  static func extractStep(from schema: JSONValue, defaultStep: Double = 1.0) -> Double {
    if case .object(let obj) = schema {
      if case .number(let step) = obj["multipleOf"] {
        return step
      }
    }
    return defaultStep
  }
  
  static func extractItems(from schema: JSONValue) -> JSONValue? {
    if case .object(let obj) = schema {
      return obj["items"]
    }
    return nil
  }
  
  static func extractPrefixItems(from schema: JSONValue) -> [JSONValue]? {
    if case .object(let obj) = schema,
       case .array(let prefixItems) = obj["prefixItems"] {
      return prefixItems
    }
    return nil
  }
  
  static func extractAdditionalItems(from schema: JSONValue) -> JSONValue? {
    if case .object(let obj) = schema {
      return obj["additionalItems"]
    }
    return nil
  }
  
  static func extractProperties(from schema: JSONValue) -> [String: JSONValue]? {
    // Boolean schemas don't have properties
    if case .boolean = schema {
      return nil
    }
    
    if case .object(let obj) = schema,
       case .object(let props) = obj["properties"] {
      return props
    }
    return nil
  }
  
  static func extractAdditionalProperties(from schema: JSONValue) -> JSONValue? {
    if case .object(let obj) = schema {
      return obj["additionalProperties"]
    }
    return nil
  }
  
  static func allowsAdditionalProperties(_ schema: JSONValue) -> Bool {
    guard let additionalProps = extractAdditionalProperties(from: schema) else {
      // If additionalProperties is not specified, default is true in JSON Schema
      return true
    }
    
    switch additionalProps {
    case .boolean(let allowed):
      return allowed
    case .object:
      // If it's an object (schema), additional properties are allowed
      return true
    default:
      return false
    }
  }
  
  static func defaultValueForSchema(_ schema: JSONValue, isRequired: Bool) -> JSONValue {
    // First check if schema has a default value
    if case .object(let schemaObj) = schema,
       let defaultValue = schemaObj["default"] {
      return defaultValue
    }
    
    guard let type = extractType(from: schema) else { return .null }
    
    switch type {
    case "string":
      // Check if this is an enum type
      if let enumValues = extractEnum(from: schema),
         let firstEnum = enumValues.first {
        // For enum fields: required fields default to first value, optional fields default to null
        return isRequired ? firstEnum : .null
      }
      // For string fields: required fields default to empty string, optional fields default to null
      return isRequired ? .string("") : .null
    case "number":
      // For number fields: required fields default to 0.0, optional fields default to null
      return isRequired ? .number(0.0) : .null
    case "integer":
      // For integer fields: required fields default to 0, optional fields default to null
      return isRequired ? .integer(0) : .null
    case "boolean":
      return .boolean(false)
    case "array":
      return .array([])
    case "object":
      return .object([:])
    case "null":
      return .null
    default:
      return .null
    }
  }
  
  static func defaultValueForType(_ type: String, isRequired: Bool) -> JSONValue {
    switch type {
    case "string":
      return isRequired ? .string("") : .null
    case "number":
      return isRequired ? .number(0.0) : .null
    case "integer":
      return isRequired ? .integer(0) : .null
    case "boolean":
      return .boolean(false)
    case "array":
      return .array([])
    case "object":
      return .object([:])
    case "null":
      return .null
    default:
      return .null
    }
  }
}
