// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// Resolves JSON Schema references including $ref, $dynamicRef, and anchors
public final class JSONSchemaReferenceResolver {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaReferenceResolver")
  
  /// Cache of resolved schemas by URI
  private var schemaCache: [String: JSONValue] = [:]
  private let maxCacheSize = 1000
  private var cacheAccessOrder: [String] = []
  
  /// Root schema for resolving internal references
  private var rootSchema: JSONValue?
  
  /// Anchors defined in the current schema ($anchor)
  private var anchors: [String: JSONValue] = [:]
  
  /// Dynamic anchors defined in the current schema ($dynamicAnchor)
  private var dynamicAnchors: [String: JSONValue] = [:]
  
  public init() {}
  
  /// Set the root schema and extract anchors
  public func setRootSchema(_ schema: JSONValue?) {
    self.rootSchema = schema
    self.schemaCache.removeAll()
    self.cacheAccessOrder.removeAll()
    self.anchors.removeAll()
    self.dynamicAnchors.removeAll()
    
    if let schema = schema {
      extractAnchors(from: schema, at: "")
    }
  }
  
  /// Add a schema to the cache with size limiting
  private func addToCache(_ key: String, _ value: JSONValue) {
    // If key already exists, remove it from the access order and add to end
    if schemaCache[key] != nil {
      cacheAccessOrder.removeAll { $0 == key }
    } else if schemaCache.count >= maxCacheSize {
      // Remove oldest entry
      let oldestKey = cacheAccessOrder.removeFirst()
      schemaCache.removeValue(forKey: oldestKey)
    }
    
    schemaCache[key] = value
    cacheAccessOrder.append(key)
  }
  
  /// Resolve a schema that may contain references
  public func resolveSchema(_ schema: JSONValue, in context: JSONSchemaValidationContext) throws -> JSONValue {
    // Check if this is a boolean schema
    if case .boolean = schema {
      return schema
    }
    
    guard case .object(var schemaObj) = schema else {
      return schema
    }
    
    // Handle $ref
    if case .string(let ref) = schemaObj["$ref"] {
      let resolved = try resolveReference(ref, baseURI: context.currentBaseURI)
      
      // After resolving $ref, merge any additional properties from the referencing schema
      if case .object(var resolvedObj) = resolved {
        // Remove $ref from the original schema
        schemaObj.removeValue(forKey: "$ref")
        
        // Merge properties (referencing schema takes precedence)
        for (key, value) in schemaObj {
          if resolvedObj[key] == nil {
            resolvedObj[key] = value
          }
        }
        
        return .object(resolvedObj)
      }
      
      return resolved
    }
    
    // Handle $dynamicRef
    if case .string(let dynamicRef) = schemaObj["$dynamicRef"] {
      let resolved = try resolveDynamicReference(dynamicRef, in: context)
      
      // Similar merging as with $ref
      if case .object(var resolvedObj) = resolved {
        schemaObj.removeValue(forKey: "$dynamicRef")
        
        for (key, value) in schemaObj {
          if resolvedObj[key] == nil {
            resolvedObj[key] = value
          }
        }
        
        return .object(resolvedObj)
      }
      
      return resolved
    }
    
    // Recursively resolve nested schemas
    var needsUpdate = false
    
    // Resolve in properties
    if case .object(let properties) = schemaObj["properties"] {
      let updatedProperties: [String: JSONValue] = try properties.reduce(into: [:]) { result, pair in
        let resolved = try resolveSchema(pair.value, in: context)
        result[pair.key] = resolved
        if !jsonValuesEqual(pair.value, resolved) {
          needsUpdate = true
        }
      }
      if needsUpdate {
        schemaObj["properties"] = .object(updatedProperties)
      }
    }
    
    // Resolve in patternProperties
    if case .object(let patternProps) = schemaObj["patternProperties"] {
      let updated: [String: JSONValue] = try patternProps.reduce(into: [:]) { result, pair in
        let resolved = try resolveSchema(pair.value, in: context)
        result[pair.key] = resolved
      }
      schemaObj["patternProperties"] = .object(updated)
    }
    
    // Resolve other schema locations...
    let schemaKeywords = [
      "items", "additionalProperties", "additionalItems", "unevaluatedProperties",
      "unevaluatedItems", "contains", "propertyNames", "if", "then", "else", "not"
    ]
    
    for keyword in schemaKeywords {
      if let subSchema = schemaObj[keyword] {
        let resolved = try resolveSchema(subSchema, in: context)
        if !jsonValuesEqual(subSchema, resolved) {
          schemaObj[keyword] = resolved
          needsUpdate = true
        }
      }
    }
    
    // Resolve arrays of schemas
    let arrayKeywords = ["allOf", "anyOf", "oneOf", "prefixItems"]
    
    for keyword in arrayKeywords {
      if case .array(let schemas) = schemaObj[keyword] {
        let resolved = try schemas.map { try resolveSchema($0, in: context) }
        if !schemas.elementsEqual(resolved, by: jsonValuesEqual) {
          schemaObj[keyword] = .array(resolved)
          needsUpdate = true
        }
      }
    }
    
    // Resolve dependentSchemas
    if case .object(let depSchemas) = schemaObj["dependentSchemas"] {
      let resolved: [String: JSONValue] = try depSchemas.reduce(into: [:]) { result, pair in
        result[pair.key] = try resolveSchema(pair.value, in: context)
      }
      schemaObj["dependentSchemas"] = .object(resolved)
    }
    
    return needsUpdate ? .object(schemaObj) : schema
  }
  
  // MARK: - Reference Resolution
  
  private func resolveReference(_ ref: String, baseURI: URL?) throws -> JSONValue {
    // Check cache first
    if let cached = schemaCache[ref] {
      // Update access order (move to end for LRU)
      cacheAccessOrder.removeAll { $0 == ref }
      cacheAccessOrder.append(ref)
      return cached
    }
    
    if ref.hasPrefix("#") {
      // Internal reference
      guard let resolved = resolveInternalReference(ref) else {
        throw JSONSchemaValidationError.referenceResolutionFailed(reference: ref)
      }
      addToCache(ref, resolved)
      return resolved
    } else {
      // External reference - not supported
      throw JSONSchemaValidationError.externalReferenceNotSupported(url: ref)
    }
  }
  
  private func resolveInternalReference(_ ref: String) -> JSONValue? {
    guard let rootSchema = rootSchema else { return nil }
    
    let fragment = String(ref.dropFirst()) // Remove #
    
    // Check if it's an anchor reference
    if !fragment.hasPrefix("/") {
      // It's an anchor, not a JSON Pointer
      return anchors[fragment]
    }
    
    // Handle JSON Pointer
    if fragment.isEmpty || fragment == "/" {
      return rootSchema
    }
    
    let components = fragment.split(separator: "/").map { String($0) }
    return resolvePointer(components, in: rootSchema)
  }
  
  private func resolveDynamicReference(_ ref: String, in context: JSONSchemaValidationContext) throws -> JSONValue {
    let fragment = ref.hasPrefix("#") ? String(ref.dropFirst()) : ref
    
    // First check if there's a dynamic anchor in the current context
    if let resolved = context.resolveDynamicAnchor(fragment) {
      return resolved
    }
    
    // Fall back to regular anchor resolution
    if let resolved = dynamicAnchors[fragment] ?? anchors[fragment] {
      return resolved
    }
    
    // Finally try as a regular reference
    return try resolveReference(ref, baseURI: context.currentBaseURI)
  }
  
  private func resolvePointer(_ components: [String], in schema: JSONValue) -> JSONValue? {
    var current = schema
    
    for component in components {
      // Decode JSON Pointer escape sequences
      let decodedComponent = component
        .replacingOccurrences(of: "~1", with: "/")
        .replacingOccurrences(of: "~0", with: "~")
      
      switch current {
      case .object(let obj):
        // Special handling for $defs
        if decodedComponent == "$defs" || decodedComponent == "definitions" {
          if let defs = obj["$defs"] {
            current = defs
          } else if let definitions = obj["definitions"] {
            current = definitions
          } else {
            return nil
          }
        } else if let value = obj[decodedComponent] {
          current = value
        } else {
          return nil
        }
        
      case .array(let arr):
        guard let index = Int(decodedComponent),
              index >= 0 && index < arr.count else {
          return nil
        }
        current = arr[index]
        
      default:
        return nil
      }
    }
    
    return current
  }
  
  // MARK: - Anchor Extraction
  
  private func extractAnchors(from schema: JSONValue, at pointer: String) {
    guard case .object(let schemaObj) = schema else { return }
    
    // Extract $anchor
    if case .string(let anchor) = schemaObj["$anchor"] {
      anchors[anchor] = schema
      logger.debug("Found anchor '\(anchor)' at pointer: \(pointer)")
    }
    
    // Extract $dynamicAnchor
    if case .string(let dynamicAnchor) = schemaObj["$dynamicAnchor"] {
      dynamicAnchors[dynamicAnchor] = schema
      logger.debug("Found dynamic anchor '\(dynamicAnchor)' at pointer: \(pointer)")
    }
    
    // Recursively extract from nested schemas
    if case .object(let properties) = schemaObj["properties"] {
      for (key, value) in properties {
        extractAnchors(from: value, at: "\(pointer)/properties/\(key)")
      }
    }
    
    if let items = schemaObj["items"] {
      extractAnchors(from: items, at: "\(pointer)/items")
    }
    
    // Extract from all other schema locations...
    let schemaKeywords = [
      "additionalProperties", "additionalItems", "unevaluatedProperties",
      "unevaluatedItems", "contains", "propertyNames", "if", "then", "else", "not"
    ]
    
    for keyword in schemaKeywords {
      if let subSchema = schemaObj[keyword] {
        extractAnchors(from: subSchema, at: "\(pointer)/\(keyword)")
      }
    }
    
    // Extract from arrays
    let arrayKeywords = ["allOf", "anyOf", "oneOf", "prefixItems"]
    for keyword in arrayKeywords {
      if case .array(let schemas) = schemaObj[keyword] {
        for (index, schema) in schemas.enumerated() {
          extractAnchors(from: schema, at: "\(pointer)/\(keyword)/\(index)")
        }
      }
    }
    
    // Extract from $defs
    if case .object(let defs) = schemaObj["$defs"] {
      for (key, value) in defs {
        extractAnchors(from: value, at: "\(pointer)/$defs/\(key)")
      }
    }
  }
  
  // MARK: - Helpers
  
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