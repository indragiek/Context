// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// Validates general keyword constraints in JSON Schema
public struct JSONSchemaKeywordValidator {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaKeywordValidator")
  
  public init() {}
  
  // MARK: - Const Validation
  
  public func validateConst(_ value: JSONValue, const: JSONValue) -> JSONSchemaValidationResult {
    if !jsonValuesEqual(value, const) {
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [.root: [.constMismatch(expected: const, actual: value)]]
      )
    }
    return JSONSchemaValidationResult()
  }
  
  // MARK: - Enum Validation
  
  public func validateEnum(_ value: JSONValue, enumValues: [JSONValue]) -> JSONSchemaValidationResult {
    for enumValue in enumValues {
      if jsonValuesEqual(value, enumValue) {
        return JSONSchemaValidationResult()
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: false,
      errors: [.root: [.enumMismatch(value: value, options: enumValues)]]
    )
  }
  
  // MARK: - Default Value
  
  public func extractDefault(from schema: [String: JSONValue]) -> JSONValue? {
    schema["default"]
  }
  
  // MARK: - Annotations
  
  public func extractAnnotations(from schema: [String: JSONValue]) -> SchemaAnnotations {
    var annotations = SchemaAnnotations()
    
    if case .string(let title) = schema["title"] {
      annotations.title = title
    }
    
    if case .string(let description) = schema["description"] {
      annotations.description = description
    }
    
    if case .array(let examples) = schema["examples"] {
      annotations.examples = examples
    }
    
    if case .boolean(let deprecated) = schema["deprecated"] {
      annotations.deprecated = deprecated
    }
    
    if case .boolean(let readOnly) = schema["readOnly"] {
      annotations.readOnly = readOnly
    }
    
    if case .boolean(let writeOnly) = schema["writeOnly"] {
      annotations.writeOnly = writeOnly
    }
    
    if case .string(let comment) = schema["$comment"] {
      annotations.comment = comment
    }
    
    return annotations
  }
  
  // MARK: - Metadata Keywords
  
  public func extractMetadata(from schema: [String: JSONValue]) -> SchemaMetadata {
    var metadata = SchemaMetadata()
    
    if case .string(let id) = schema["$id"] {
      metadata.id = id
    }
    
    if case .string(let schemaUri) = schema["$schema"] {
      metadata.schema = schemaUri
    }
    
    if case .string(let anchor) = schema["$anchor"] {
      metadata.anchor = anchor
    }
    
    if case .string(let dynamicAnchor) = schema["$dynamicAnchor"] {
      metadata.dynamicAnchor = dynamicAnchor
    }
    
    if case .object(let vocabulary) = schema["$vocabulary"] {
      metadata.vocabulary = vocabulary.compactMapValues { value in
        if case .boolean(let enabled) = value {
          return enabled
        }
        return nil
      }
    }
    
    return metadata
  }
  
  // MARK: - JSON Value Equality
  
  private func jsonValuesEqual(_ a: JSONValue, _ b: JSONValue) -> Bool {
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
    case (.integer(let a), .number(let b)):
      // Integer can equal number if they're the same value
      return Double(a) == b
    case (.number(let a), .integer(let b)):
      // Number can equal integer if they're the same value
      return a == Double(b)
    case (.array(let a), .array(let b)):
      return a.count == b.count && zip(a, b).allSatisfy(jsonValuesEqual)
    case (.object(let a), .object(let b)):
      return a.keys == b.keys && a.keys.allSatisfy { key in
        jsonValuesEqual(a[key]!, b[key]!)
      }
    default:
      return false
    }
  }
}

// MARK: - Supporting Types

/// Schema annotations that provide metadata about the schema
public struct SchemaAnnotations {
  public var title: String?
  public var description: String?
  public var examples: [JSONValue]?
  public var deprecated: Bool = false
  public var readOnly: Bool = false
  public var writeOnly: Bool = false
  public var comment: String?
  
  public init() {}
}

/// Schema metadata for identification and referencing
public struct SchemaMetadata {
  public var id: String?
  public var schema: String?
  public var anchor: String?
  public var dynamicAnchor: String?
  public var vocabulary: [String: Bool]?
  
  public init() {}
}

// MARK: - Extended Validators

extension JSONSchemaKeywordValidator {
  
  /// Validate property names against a schema
  public func validatePropertyNames(
    _ propertyNames: Set<String>,
    schema: JSONValue,
    validator: (JSONValue, JSONValue) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    var allErrors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:]
    
    for name in propertyNames {
      let nameValue = JSONValue.string(name)
      let result = try await validator(nameValue, schema)
      if !result.isValid {
        // Add property name to error path
        if result.errors.isEmpty {
          // If no specific errors are provided, add a generic error
          let path = JSONSchemaValidationPath(components: [.root, .property(name)])
          allErrors[path] = [.invalidSchema(reason: "Property name '\(name)' does not match required schema")]
        } else {
          for (path, errors) in result.errors {
            let newPath = path == .root ? 
              JSONSchemaValidationPath(components: [.root, .property(name)]) :
              JSONSchemaValidationPath(components: path.components + [.property(name)])
            allErrors[newPath] = errors
          }
        }
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: allErrors.isEmpty,
      errors: allErrors
    )
  }
  
  /// Extract pattern properties from schema
  public func extractPatternProperties(from schema: [String: JSONValue]) -> [(pattern: String, schema: JSONValue)]? {
    guard case .object(let patternProps) = schema["patternProperties"] else {
      return nil
    }
    
    return patternProps.map { (pattern: $0.key, schema: $0.value) }
  }
  
  /// Match property names against pattern properties
  public func matchPatternProperties(
    propertyName: String,
    patternProperties: [(pattern: String, schema: JSONValue)]
  ) async -> [(pattern: String, schema: JSONValue)] {
    var matches: [(pattern: String, schema: JSONValue)] = []
    
    for (pattern, schema) in patternProperties {
      if await propertyName.matchesPattern(pattern) {
        matches.append((pattern, schema))
      }
    }
    
    return matches
  }
}