// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite("JSON Schema Composition Validator")
struct JSONSchemaCompositionValidatorTests {
  let validator = JSONSchemaCompositionValidator()
  
  // MARK: - Test Helpers
  
  // Simple validator that checks type and minimum/maximum constraints
  private func createMockValidator() -> (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult {
    return { value, schema, context in
      guard case .object(let schemaObj) = schema else {
        return JSONSchemaValidationResult()
      }
      
      var hasConstraints = false
      var isValid = true
      var errors: [JSONSchemaValidationError] = []
      
      // Type check
      if case .string(let expectedType) = schemaObj["type"] {
        hasConstraints = true
        let actualType: String
        switch value {
        case .string: actualType = "string"
        case .number, .integer: actualType = "number"
        case .boolean: actualType = "boolean"
        case .array: actualType = "array"
        case .object: actualType = "object"
        case .null: actualType = "null"
        }
        
        if actualType != expectedType {
          isValid = false
          errors.append(.invalidType(expected: [expectedType], actual: actualType))
        }
      }
      
      // Minimum check for numbers
      if case .number(let num) = value {
        if let min = schemaObj["minimum"] {
          hasConstraints = true
          if case .number(let minVal) = min, num < minVal {
            isValid = false
            errors.append(.valueTooSmall(value: num, limit: minVal, exclusive: false))
          }
        }
        if let max = schemaObj["maximum"] {
          hasConstraints = true
          if case .number(let maxVal) = max, num > maxVal {
            isValid = false
            errors.append(.valueTooLarge(value: num, limit: maxVal, exclusive: false))
          }
        }
      }
      
      // Also check minimum/maximum for integers
      if case .integer(let num) = value {
        if let min = schemaObj["minimum"] {
          hasConstraints = true
          if case .number(let minVal) = min, Double(num) < minVal {
            isValid = false
            errors.append(.valueTooSmall(value: Double(num), limit: minVal, exclusive: false))
          }
        }
        if let max = schemaObj["maximum"] {
          hasConstraints = true
          if case .number(let maxVal) = max, Double(num) > maxVal {
            isValid = false
            errors.append(.valueTooLarge(value: Double(num), limit: maxVal, exclusive: false))
          }
        }
      }
      
      // Mark properties as evaluated for objects
      if case .object(let obj) = value {
        context.markAllPropertiesEvaluated(Set(obj.keys))
      }
      
      // If schema has no constraints, it validates everything
      if !hasConstraints {
        return JSONSchemaValidationResult()
      }
      
      return JSONSchemaValidationResult(
        isValid: isValid,
        errors: isValid ? [:] : [context.currentPath: errors]
      )
    }
  }
  
  // MARK: - AllOf Tests
  
  @Test("AllOf with all schemas passing")
  func allOfAllPass() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("number")]),
      .object(["minimum": .number(0)]),
      .object(["maximum": .number(100)])
    ]
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateAllOf(
      .number(50),
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
  }
  
  @Test("AllOf with one schema failing")
  func allOfOneFails() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("number")]),
      .object(["minimum": .number(0)]),
      .object(["maximum": .number(10)])
    ]
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateAllOf(
      .number(50),
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(!result.isValid)
    if case .allOfValidationFailed(let failures) = result.errors[.root]?.first {
      #expect(failures.count == 1)
      #expect(failures.keys.contains(2)) // Third schema failed
    } else {
      Issue.record("Expected allOfValidationFailed error")
    }
  }
  
  @Test("AllOf with empty schemas array")
  func allOfEmptySchemas() async throws {
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateAllOf(
      .string("test"),
      schemas: [],
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
  }
  
  @Test("AllOf merges evaluated properties")
  func allOfMergesEvaluated() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("object")]),
      .object(["type": .string("object")])
    ]
    
    let context = JSONSchemaValidationContext()
    let obj: JSONValue = .object(["foo": .string("bar"), "baz": .number(42)])
    
    let result = try await validator.validateAllOf(
      obj,
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
    // Both schemas should have marked the properties as evaluated
    let unevaluated = context.getUnevaluatedProperties(for: ["foo": .string("bar"), "baz": .number(42)])
    #expect(unevaluated.isEmpty)
  }
  
  // MARK: - AnyOf Tests
  
  @Test("AnyOf with one schema passing")
  func anyOfOnePass() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("string")]),
      .object(["type": .string("number")]),
      .object(["type": .string("boolean")])
    ]
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateAnyOf(
      .number(42),
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
  }
  
  @Test("AnyOf with multiple schemas passing")
  func anyOfMultiplePass() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("number")]),
      .object(["minimum": .number(0)]),
      .object(["maximum": .number(100)])
    ]
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateAnyOf(
      .number(50),
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
  }
  
  @Test("AnyOf with all schemas failing")
  func anyOfAllFail() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("string")]),
      .object(["type": .string("boolean")]),
      .object(["type": .string("null")])
    ]
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateAnyOf(
      .number(42),
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(!result.isValid)
    #expect(result.errors[.root]?.contains { $0 == .anyOfValidationFailed } == true)
  }
  
  @Test("AnyOf with empty schemas array")
  func anyOfEmptySchemas() async throws {
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateAnyOf(
      .string("test"),
      schemas: [],
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
  }
  
  // MARK: - OneOf Tests
  
  @Test("OneOf with exactly one schema passing")
  func oneOfExactlyOnePass() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("string")]),
      .object(["type": .string("number")]),
      .object(["type": .string("boolean")])
    ]
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateOneOf(
      .number(42),
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
  }
  
  @Test("OneOf with no schemas passing")
  func oneOfNonePass() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("string")]),
      .object(["type": .string("boolean")]),
      .object(["type": .string("null")])
    ]
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateOneOf(
      .number(42),
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(!result.isValid)
    if case .oneOfValidationFailed(let validCount) = result.errors[.root]?.first {
      #expect(validCount == 0)
    } else {
      Issue.record("Expected oneOfValidationFailed error")
    }
  }
  
  @Test("OneOf with multiple schemas passing")
  func oneOfMultiplePass() async throws {
    let schemas: [JSONValue] = [
      .object(["type": .string("number")]),
      .object(["minimum": .number(0)]),
      .object(["maximum": .number(100)])
    ]
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateOneOf(
      .number(50),
      schemas: schemas,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(!result.isValid)
    if case .oneOfValidationFailed(let validCount) = result.errors[.root]?.first {
      #expect(validCount >= 2) // At least two schemas pass (early exit optimization)
    } else {
      Issue.record("Expected oneOfValidationFailed error")
    }
  }
  
  // MARK: - Not Tests
  
  @Test("Not with schema failing (which means validation passes)")
  func notSchemaFails() async throws {
    let schema: JSONValue = .object(["type": .string("string")])
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateNot(
      .number(42),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
  }
  
  @Test("Not with schema passing (which means validation fails)")
  func notSchemaPasses() async throws {
    let schema: JSONValue = .object(["type": .string("number")])
    
    let context = JSONSchemaValidationContext()
    let result = try await validator.validateNot(
      .number(42),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(!result.isValid)
    #expect(result.errors[.root]?.contains { $0 == .notValidationFailed } == true)
  }
  
  // MARK: - Constraint Merging Tests
  
  @Test("Merge type constraints")
  func mergeTypeConstraints() {
    let schemas: [JSONValue] = [
      .object(["type": .string("string")]),
      .object(["type": .array([.string("string"), .string("null")])]),
      .object(["type": .string("string")])
    ]
    
    let merged = validator.mergeTypeConstraints(from: schemas)
    
    // Should get intersection: only "string" is common to all
    #expect(merged == .string("string"))
  }
  
  @Test("Merge numeric constraints")
  func mergeNumericConstraints() {
    let schemas: [JSONValue] = [
      .object(["minimum": .number(10), "maximum": .number(100)]),
      .object(["minimum": .number(20), "maximum": .number(80)]),
      .object(["minimum": .number(15), "maximum": .number(90)])
    ]
    
    let merged = validator.mergeNumericConstraints(from: schemas)
    
    // Should take most restrictive: min=20, max=80
    #expect(merged["minimum"] == .number(20))
    #expect(merged["maximum"] == .number(80))
  }
  
  @Test("Merge string constraints")
  func mergeStringConstraints() {
    let schemas: [JSONValue] = [
      .object(["minLength": .integer(5), "maxLength": .integer(50)]),
      .object(["minLength": .integer(10), "maxLength": .integer(40)]),
      .object(["minLength": .integer(8), "maxLength": .integer(45)])
    ]
    
    let merged = validator.mergeStringConstraints(from: schemas)
    
    // Should take most restrictive: minLength=10, maxLength=40
    #expect(merged["minLength"] == .integer(10))
    #expect(merged["maxLength"] == .integer(40))
  }
}