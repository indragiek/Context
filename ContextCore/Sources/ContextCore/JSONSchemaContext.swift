// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// Options for configuring JSON Schema validation behavior
public struct JSONSchemaValidationOptions {
  /// Whether to validate format annotations (default: true)
  public var validateFormats: Bool
  
  /// Whether to enforce vocabulary constraints (default: false)
  public var enforceVocabularies: Bool
  
  /// Whether to collect annotations during validation (default: true)
  public var collectAnnotations: Bool
  
  /// Maximum regex evaluation time in seconds to prevent ReDoS (default: 2.0)
  public var maxRegexEvaluationTime: TimeInterval
  
  /// Content validator for contentSchema validation
  public var contentValidator: ((JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult)?
  
  public init(
    validateFormats: Bool = true,
    enforceVocabularies: Bool = false,
    collectAnnotations: Bool = true,
    maxRegexEvaluationTime: TimeInterval = 2.0,
    contentValidator: ((JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult)? = nil
  ) {
    self.validateFormats = validateFormats
    self.enforceVocabularies = enforceVocabularies
    self.collectAnnotations = collectAnnotations
    self.maxRegexEvaluationTime = maxRegexEvaluationTime
    self.contentValidator = contentValidator
  }
}

/// Context for tracking validation state across schema evaluation
public final class JSONSchemaValidationContext {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaValidationContext")
  
  /// Properties that have been evaluated at each path
  private var evaluatedProperties: [JSONSchemaValidationPath: Set<String>] = [:]
  
  /// Array indices that have been evaluated at each path
  private var evaluatedItems: [JSONSchemaValidationPath: Set<Int>] = [:]
  
  /// Stack of current schema paths for tracking nested validation
  private var schemaStack: [SchemaLocation] = []
  
  /// Base URI stack for resolving relative references
  private var baseURIStack: [URL] = []
  
  /// Current validation path
  private(set) public var currentPath: JSONSchemaValidationPath = .root
  
  /// Dialect identifier from $schema
  public var dialect: String?
  
  /// Vocabularies in use
  public var vocabularies: Set<String> = []
  
  /// Dynamic anchors defined in the current schema
  private var dynamicAnchors: [String: JSONValue] = [:]
  
  /// Dynamic scope stack for $dynamicRef resolution
  private var dynamicScopeStack: [[String: JSONValue]] = []
  
  /// Validation options
  public let options: JSONSchemaValidationOptions
  
  /// Collected annotations
  private var annotations: [JSONSchemaValidationPath: [String: JSONValue]] = [:]
  
  public init(options: JSONSchemaValidationOptions = JSONSchemaValidationOptions()) {
    self.options = options
  }
  
  // MARK: - Path Management
  
  public func pushPath(property: String) {
    currentPath = currentPath.appending(property: property)
  }
  
  public func pushPath(index: Int) {
    currentPath = currentPath.appending(index: index)
  }
  
  public func popPath() {
    guard !currentPath.components.isEmpty else { return }
    currentPath = JSONSchemaValidationPath(components: Array(currentPath.components.dropLast()))
  }
  
  // MARK: - Evaluated Properties/Items Tracking
  
  public func markPropertyEvaluated(_ property: String) {
    evaluatedProperties[currentPath, default: []].insert(property)
    logger.debug("Marked property '\(property)' as evaluated at path: \(self.currentPath)")
  }
  
  public func markItemEvaluated(_ index: Int) {
    evaluatedItems[currentPath, default: []].insert(index)
    logger.debug("Marked item at index \(index) as evaluated at path: \(self.currentPath)")
  }
  
  public func markAllPropertiesEvaluated(_ properties: Set<String>) {
    evaluatedProperties[currentPath, default: []].formUnion(properties)
    logger.debug("Marked \(properties.count) properties as evaluated at path: \(self.currentPath)")
  }
  
  public func markAllItemsEvaluated(count: Int) {
    let indices = Set(0..<count)
    evaluatedItems[currentPath, default: []].formUnion(indices)
    logger.debug("Marked all \(count) items as evaluated at path: \(self.currentPath)")
  }
  
  public func getUnevaluatedProperties(for object: [String: JSONValue]) -> Set<String> {
    let allProperties = Set(object.keys)
    let evaluated = evaluatedProperties[currentPath] ?? []
    return allProperties.subtracting(evaluated)
  }
  
  public func getUnevaluatedItems(for array: [JSONValue]) -> Set<Int> {
    let allIndices = Set(0..<array.count)
    let evaluated = evaluatedItems[currentPath] ?? []
    return allIndices.subtracting(evaluated)
  }
  
  // MARK: - Annotation Collection
  
  public func collectAnnotation(keyword: String, value: JSONValue) {
    guard options.collectAnnotations else { return }
    annotations[currentPath, default: [:]][keyword] = value
    logger.debug("Collected annotation '\(keyword)' at path: \(self.currentPath)")
  }
  
  public func getCollectedAnnotations() -> [JSONSchemaValidationPath: [String: JSONValue]] {
    annotations
  }
  
  // MARK: - Schema Stack Management
  
  public func pushSchema(_ location: SchemaLocation) {
    schemaStack.append(location)
    
    // Update base URI if schema has $id
    if case .object(let schemaObj) = location.schema,
       case .string(let id) = schemaObj["$id"],
       let baseURI = URL(string: id) {
      baseURIStack.append(baseURI)
    }
    
    // Extract dynamic anchors and push to dynamic scope
    if case .object(let schemaObj) = location.schema {
      var dynamicAnchorsInSchema: [String: JSONValue] = [:]
      
      if case .string(let anchor) = schemaObj["$dynamicAnchor"] {
        dynamicAnchors[anchor] = location.schema
        dynamicAnchorsInSchema[anchor] = location.schema
      }
      
      // Push dynamic anchors to dynamic scope stack
      dynamicScopeStack.append(dynamicAnchorsInSchema)
    } else {
      // Push empty scope for non-object schemas
      dynamicScopeStack.append([:])
    }
  }
  
  public func popSchema() {
    guard let popped = schemaStack.popLast() else { return }
    
    // Pop base URI if this schema had $id
    if case .object(let schemaObj) = popped.schema,
       schemaObj["$id"] != nil {
      _ = baseURIStack.popLast()
    }
    
    // Pop dynamic scope
    _ = dynamicScopeStack.popLast()
  }
  
  public var currentBaseURI: URL? {
    baseURIStack.last
  }
  
  public func resolveDynamicAnchor(_ anchor: String) -> JSONValue? {
    // Search through dynamic scope stack from top to bottom
    for scope in dynamicScopeStack.reversed() {
      if let schema = scope[anchor] {
        return schema
      }
    }
    // Fall back to static resolution
    return dynamicAnchors[anchor]
  }
  
  // MARK: - Validation State
  
  /// Create a child context for nested validation
  public func createChildContext() -> JSONSchemaValidationContext {
    let child = JSONSchemaValidationContext(options: options)
    child.currentPath = currentPath
    child.dialect = dialect
    child.vocabularies = vocabularies
    child.baseURIStack = baseURIStack
    child.dynamicAnchors = dynamicAnchors
    child.dynamicScopeStack = dynamicScopeStack
    // Don't copy evaluated properties/items - they're specific to each validation pass
    return child
  }
  
  /// Merge evaluated properties/items from a child context
  public func mergeEvaluated(from child: JSONSchemaValidationContext) {
    for (path, props) in child.evaluatedProperties {
      evaluatedProperties[path, default: []].formUnion(props)
    }
    for (path, items) in child.evaluatedItems {
      evaluatedItems[path, default: []].formUnion(items)
    }
    
    // Merge annotations
    for (path, anns) in child.annotations {
      annotations[path, default: [:]] = annotations[path, default: [:]].merging(anns) { _, new in new }
    }
  }
}

/// Represents a location in a schema document
public struct SchemaLocation {
  public let schema: JSONValue
  public let pointer: String // JSON Pointer to this location
  public let baseURI: URL?
  
  public init(schema: JSONValue, pointer: String = "", baseURI: URL? = nil) {
    self.schema = schema
    self.pointer = pointer
    self.baseURI = baseURI
  }
}