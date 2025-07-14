// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// Validates composition keywords (allOf, anyOf, oneOf, not) in JSON Schema
public struct JSONSchemaCompositionValidator {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaCompositionValidator")
  
  public init() {}
  
  // MARK: - AllOf Validation
  
  public func validateAllOf(
    _ value: JSONValue,
    schemas: [JSONValue],
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    guard !schemas.isEmpty else {
      return JSONSchemaValidationResult()
    }
    
    var allErrors: [Int: [JSONSchemaValidationError]] = [:]
    var mergedResult = JSONSchemaValidationResult()
    
    // Each schema must validate
    for (index, schema) in schemas.enumerated() {
      let childContext = context.createChildContext()
      let result = try await validator(value, schema, childContext)
      
      if !result.isValid {
        // Collect errors by schema index
        let errors = result.errors.values.flatMap { $0 }
        if !errors.isEmpty {
          allErrors[index] = errors
        }
      }
      
      // Merge results even if valid - we need to track evaluated properties/items
      mergedResult = mergedResult.merging(result)
      
      // Merge evaluated properties/items back to parent context
      context.mergeEvaluated(from: childContext)
    }
    
    if !allErrors.isEmpty {
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [.root: [.allOfValidationFailed(failures: allErrors)]]
      )
    }
    
    return mergedResult
  }
  
  // MARK: - AnyOf Validation
  
  public func validateAnyOf(
    _ value: JSONValue,
    schemas: [JSONValue],
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    guard !schemas.isEmpty else {
      return JSONSchemaValidationResult()
    }
    
    var anyValid = false
    var validResults: [JSONSchemaValidationResult] = []
    
    // At least one schema must validate
    for schema in schemas {
      let childContext = context.createChildContext()
      let result = try await validator(value, schema, childContext)
      
      if result.isValid {
        anyValid = true
        validResults.append(result)
        // For anyOf, we merge evaluated properties/items from all valid schemas
        context.mergeEvaluated(from: childContext)
      }
    }
    
    if !anyValid {
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [.root: [.anyOfValidationFailed]]
      )
    }
    
    // Merge all valid results
    var mergedResult = JSONSchemaValidationResult()
    for result in validResults {
      mergedResult = mergedResult.merging(result)
    }
    
    return mergedResult
  }
  
  // MARK: - OneOf Validation
  
  public func validateOneOf(
    _ value: JSONValue,
    schemas: [JSONValue],
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    guard !schemas.isEmpty else {
      return JSONSchemaValidationResult()
    }
    
    var validCount = 0
    var validResult: JSONSchemaValidationResult?
    var validContext: JSONSchemaValidationContext?
    
    // Exactly one schema must validate
    for schema in schemas {
      let childContext = context.createChildContext()
      let result = try await validator(value, schema, childContext)
      
      if result.isValid {
        validCount += 1
        validResult = result
        validContext = childContext
        
        // Early exit if we already have more than one valid
        if validCount > 1 {
          break
        }
      }
    }
    
    if validCount != 1 {
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [.root: [.oneOfValidationFailed(validCount: validCount)]]
      )
    }
    
    // Merge evaluated properties/items from the single valid schema
    if let validContext = validContext {
      context.mergeEvaluated(from: validContext)
    }
    
    return validResult ?? JSONSchemaValidationResult()
  }
  
  // MARK: - Not Validation
  
  public func validateNot(
    _ value: JSONValue,
    schema: JSONValue,
    context: JSONSchemaValidationContext,
    validator: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult
  ) async throws -> JSONSchemaValidationResult {
    // Schema must NOT validate
    let childContext = context.createChildContext()
    let result = try await validator(value, schema, childContext)
    
    if result.isValid {
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [.root: [.notValidationFailed]]
      )
    }
    
    // For 'not', we don't merge evaluated properties/items
    return JSONSchemaValidationResult()
  }
  
  // MARK: - Helpers for Merging Constraints
  
  /// Extract and merge type constraints from multiple schemas
  public func mergeTypeConstraints(from schemas: [JSONValue]) -> JSONValue? {
    var typeSetsBySchema: [Set<String>] = []
    
    for schema in schemas {
      guard case .object(let schemaObj) = schema else { continue }
      
      if let typeValue = schemaObj["type"] {
        var types: Set<String> = []
        if case .string(let type) = typeValue {
          types.insert(type)
        } else if case .array(let typeArray) = typeValue {
          for type in typeArray {
            if case .string(let t) = type {
              types.insert(t)
            }
          }
        }
        if !types.isEmpty {
          typeSetsBySchema.append(types)
        }
      }
    }
    
    guard !typeSetsBySchema.isEmpty else { return nil }
    
    // Find intersection of all type sets
    var intersection = typeSetsBySchema[0]
    for i in 1..<typeSetsBySchema.count {
      intersection = intersection.intersection(typeSetsBySchema[i])
    }
    
    guard !intersection.isEmpty else { return nil }
    
    if intersection.count == 1 {
      return .string(intersection.first!)
    } else {
      return .array(intersection.sorted().map { .string($0) })
    }
  }
  
  /// Merge numeric constraints taking the most restrictive values
  public func mergeNumericConstraints(from schemas: [JSONValue]) -> [String: JSONValue] {
    var constraints: [String: JSONValue] = [:]
    
    var minValues: [Double] = []
    var maxValues: [Double] = []
    var exclusiveMinValues: [Double] = []
    var exclusiveMaxValues: [Double] = []
    var multipleOfValues: [Double] = []
    
    for schema in schemas {
      guard case .object(let schemaObj) = schema else { continue }
      
      if let min = extractNumericValue(schemaObj["minimum"]) {
        minValues.append(min)
      }
      if let max = extractNumericValue(schemaObj["maximum"]) {
        maxValues.append(max)
      }
      if let exMin = extractNumericValue(schemaObj["exclusiveMinimum"]) {
        exclusiveMinValues.append(exMin)
      }
      if let exMax = extractNumericValue(schemaObj["exclusiveMaximum"]) {
        exclusiveMaxValues.append(exMax)
      }
      if let multiple = extractNumericValue(schemaObj["multipleOf"]) {
        multipleOfValues.append(multiple)
      }
    }
    
    // Take most restrictive values
    if !minValues.isEmpty {
      constraints["minimum"] = .number(minValues.max()!)
    }
    if !maxValues.isEmpty {
      constraints["maximum"] = .number(maxValues.min()!)
    }
    if !exclusiveMinValues.isEmpty {
      constraints["exclusiveMinimum"] = .number(exclusiveMinValues.max()!)
    }
    if !exclusiveMaxValues.isEmpty {
      constraints["exclusiveMaximum"] = .number(exclusiveMaxValues.min()!)
    }
    
    // For multipleOf, find LCM (least common multiple)
    if !multipleOfValues.isEmpty {
      // Simplified: just use the first value for now
      // A proper implementation would calculate LCM
      constraints["multipleOf"] = .number(multipleOfValues[0])
    }
    
    return constraints
  }
  
  /// Merge string constraints taking the most restrictive values
  public func mergeStringConstraints(from schemas: [JSONValue]) -> [String: JSONValue] {
    var constraints: [String: JSONValue] = [:]
    
    var minLengths: [Int] = []
    var maxLengths: [Int] = []
    var patterns: [String] = []
    
    for schema in schemas {
      guard case .object(let schemaObj) = schema else { continue }
      
      if case .integer(let min) = schemaObj["minLength"] {
        minLengths.append(Int(min))
      }
      if case .integer(let max) = schemaObj["maxLength"] {
        maxLengths.append(Int(max))
      }
      if case .string(let pattern) = schemaObj["pattern"] {
        patterns.append(pattern)
      }
    }
    
    // Take most restrictive values
    if !minLengths.isEmpty {
      constraints["minLength"] = .integer(Int64(minLengths.max()!))
    }
    if !maxLengths.isEmpty {
      constraints["maxLength"] = .integer(Int64(maxLengths.min()!))
    }
    
    // For patterns, we'd need to combine them (AND operation)
    // For now, just include all as a note
    if patterns.count == 1 {
      constraints["pattern"] = .string(patterns[0])
    }
    // Multiple patterns would require a complex regex combination
    
    return constraints
  }
  
  private func extractNumericValue(_ value: JSONValue?) -> Double? {
    switch value {
    case .number(let n):
      return n
    case .integer(let i):
      return Double(i)
    default:
      return nil
    }
  }
}