// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// Validates conditional keywords (if/then/else) and handles unevaluated properties/items
public struct JSONSchemaConditionalValidator {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaConditionalValidator")
  
  public init() {}
  
  // MARK: - If/Then/Else Validation
  
  public func validateConditional(
    _ value: JSONValue,
    schema: [String: JSONValue],
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    guard let ifSchema = schema["if"] else {
      // No conditional validation needed
      return JSONSchemaValidationResult()
    }
    
    // Evaluate the 'if' condition
    let ifContext = context.createChildContext()
    let ifResult = try await validator(value, ifSchema, ifContext)
    
    if ifResult.isValid {
      // 'if' succeeded, apply 'then' if present
      if let thenSchema = schema["then"] {
        let thenContext = context.createChildContext()
        let thenResult = try await validator(value, thenSchema, thenContext)
        
        // Merge evaluated properties/items from both if and then
        context.mergeEvaluated(from: ifContext)
        context.mergeEvaluated(from: thenContext)
        
        if !thenResult.isValid {
          var errors = thenResult.errors
          errors[.root, default: []].append(.conditionalValidationFailed(branch: "then"))
          return JSONSchemaValidationResult(isValid: false, errors: errors)
        }
        
        return thenResult
      } else {
        // No 'then' branch, just merge if context
        context.mergeEvaluated(from: ifContext)
      }
    } else {
      // 'if' failed, apply 'else' if present
      if let elseSchema = schema["else"] {
        let elseContext = context.createChildContext()
        let elseResult = try await validator(value, elseSchema, elseContext)
        
        // Only merge evaluated from else (not from failed if)
        context.mergeEvaluated(from: elseContext)
        
        if !elseResult.isValid {
          var errors = elseResult.errors
          errors[.root, default: []].append(.conditionalValidationFailed(branch: "else"))
          return JSONSchemaValidationResult(isValid: false, errors: errors)
        }
        
        return elseResult
      }
    }
    
    return JSONSchemaValidationResult()
  }
  
  // MARK: - Dependent Schemas Validation
  
  public func validateDependentSchemas(
    _ value: [String: JSONValue],
    dependentSchemas: [String: JSONValue],
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    var allErrors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:]
    
    for (propertyName, dependentSchema) in dependentSchemas {
      // Check if the property exists
      if value[propertyName] != nil {
        // Property exists, validate entire object against dependent schema
        let result = try await validator(.object(value), dependentSchema, context)
        
        if !result.isValid {
          // Merge errors
          for (path, errors) in result.errors {
            allErrors[path, default: []].append(contentsOf: errors)
          }
          
          // Add context about which dependent schema failed
          allErrors[.root, default: []].append(
            .invalidSchema(reason: "Object does not match schema required when '\(propertyName)' is present")
          )
        }
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: allErrors.isEmpty,
      errors: allErrors
    )
  }
  
  // MARK: - Unevaluated Properties Validation
  
  public func validateUnevaluatedProperties(
    _ value: [String: JSONValue],
    unevaluatedPropertiesSchema: JSONValue,
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    // Get properties that haven't been evaluated
    let unevaluatedProps = context.getUnevaluatedProperties(for: value)
    
    if unevaluatedProps.isEmpty {
      return JSONSchemaValidationResult()
    }
    
    // Check if unevaluatedProperties is false
    if case .boolean(false) = unevaluatedPropertiesSchema {
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [.root: [.unevaluatedPropertiesFound(properties: Array(unevaluatedProps))]]
      )
    }
    
    // Validate each unevaluated property against the schema
    var allErrors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:]
    
    for propertyName in unevaluatedProps {
      if let propertyValue = value[propertyName] {
        context.pushPath(property: propertyName)
        
        let result = try await validator(propertyValue, unevaluatedPropertiesSchema, context)
        
        if !result.isValid {
          for (path, errors) in result.errors {
            let fullPath = path == .root ? context.currentPath : path
            allErrors[fullPath, default: []].append(contentsOf: errors)
          }
        }
        
        context.popPath()
        
        if result.isValid {
          // Mark as evaluated if validation passes (at object level after popping context)
          context.markPropertyEvaluated(propertyName)
        }
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: allErrors.isEmpty,
      errors: allErrors
    )
  }
  
  // MARK: - Unevaluated Items Validation
  
  public func validateUnevaluatedItems(
    _ value: [JSONValue],
    unevaluatedItemsSchema: JSONValue,
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    // Get items that haven't been evaluated
    let unevaluatedIndices = context.getUnevaluatedItems(for: value)
    
    if unevaluatedIndices.isEmpty {
      return JSONSchemaValidationResult()
    }
    
    // Check if unevaluatedItems is false
    if case .boolean(false) = unevaluatedItemsSchema {
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [.root: [.unevaluatedItemsFound(indices: Array(unevaluatedIndices))]]
      )
    }
    
    // Validate each unevaluated item against the schema
    var allErrors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:]
    
    for index in unevaluatedIndices {
      if index < value.count {
        context.pushPath(index: index)
        
        let result = try await validator(value[index], unevaluatedItemsSchema, context)
        
        if !result.isValid {
          for (path, errors) in result.errors {
            let fullPath = path == .root ? context.currentPath : path
            allErrors[fullPath, default: []].append(contentsOf: errors)
          }
        }
        
        context.popPath()
        
        if result.isValid {
          // Mark as evaluated if validation passes (at array level after popping context)
          context.markItemEvaluated(index)
        }
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: allErrors.isEmpty,
      errors: allErrors
    )
  }
  
  // MARK: - Contains Validation
  
  public func validateContains(
    _ value: [JSONValue],
    containsSchema: JSONValue,
    minContains: Int?,
    maxContains: Int?,
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    var validCount = 0
    var validIndices: [Int] = []
    
    // Check each item against the contains schema
    for (index, item) in value.enumerated() {
      context.pushPath(index: index)
      defer { context.popPath() }
      
      let result = try await validator(item, containsSchema, context)
      if result.isValid {
        validCount += 1
        validIndices.append(index)
      }
    }
    
    // Check min/max constraints
    let minRequired = minContains ?? 1 // Default minimum is 1
    let maxAllowed = maxContains ?? Int.max
    
    if validCount < minRequired || validCount > maxAllowed {
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [.root: [.containsValidationFailed(
          minContains: minContains,
          maxContains: maxContains,
          actualCount: validCount
        )]]
      )
    }
    
    // Mark the valid items as evaluated for contains
    for index in validIndices {
      context.markItemEvaluated(index)
    }
    
    return JSONSchemaValidationResult()
  }
  
  // MARK: - Pattern Properties Validation
  
  public func validatePatternProperties(
    _ value: [String: JSONValue],
    patternProperties: [String: JSONValue],
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    var allErrors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:]
    
    for (pattern, patternSchema) in patternProperties {
      for (propertyName, propertyValue) in value {
        let matches = await propertyName.matchesPattern(pattern)
        if matches {
          context.pushPath(property: propertyName)
          
          let result = try await validator(propertyValue, patternSchema, context)
          
          if !result.isValid {
            for (path, errors) in result.errors {
              let fullPath = path == .root ? context.currentPath : path
              allErrors[fullPath, default: []].append(contentsOf: errors)
            }
          }
          
          context.popPath()
          
          // Mark property as evaluated at the object level (after popping back to object context)
          context.markPropertyEvaluated(propertyName)
        }
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: allErrors.isEmpty,
      errors: allErrors
    )
  }
}