// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite("JSON Schema Conditional Validator")
struct JSONSchemaConditionalValidatorTests {
  let validator = JSONSchemaConditionalValidator()
  
  // MARK: - Test Helpers
  
  private func createMockValidator() -> (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult {
    return { value, schema, context in
      guard case .object(let schemaObj) = schema else {
        return JSONSchemaValidationResult()
      }
      
      // Simple type validation
      if case .string(let expectedType) = schemaObj["type"] {
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
          return JSONSchemaValidationResult(
            isValid: false,
            errors: [context.currentPath: [.invalidType(expected: [expectedType], actual: actualType)]]
          )
        }
      }
      
      // Properties validation for objects
      if case .object(let obj) = value,
         case .object(let props) = schemaObj["properties"] {
        for (key, _) in props {
          if obj[key] != nil {
            context.markPropertyEvaluated(key)
          }
        }
      }
      
      // Items validation for arrays
      if case .array(let arr) = value {
        for i in 0..<arr.count {
          context.markItemEvaluated(i)
        }
      }
      
      // Required properties check
      if case .object(let obj) = value,
         case .array(let required) = schemaObj["required"] {
        for req in required {
          if case .string(let prop) = req, obj[prop] == nil {
            return JSONSchemaValidationResult(
              isValid: false,
              errors: [context.currentPath: [.missingRequiredProperty(property: prop)]]
            )
          }
        }
      }
      
      return JSONSchemaValidationResult()
    }
  }
  
  // MARK: - If/Then/Else Tests
  
  @Test("If condition passes, then branch validates")
  func ifThenValidation() async throws {
    let schema: [String: JSONValue] = [
      "if": .object(["type": .string("string")]),
      "then": .object(["minLength": .integer(5)])
    ]
    
    let context = JSONSchemaValidationContext()
    
    // String that satisfies 'then' condition
    let result1 = try await validator.validateConditional(
      .string("hello world"),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    #expect(result1.isValid)
    
    // String that doesn't satisfy 'then' condition (too short)
    let mockValidatorWithLength: (JSONValue, JSONValue, JSONSchemaValidationContext) async throws -> JSONSchemaValidationResult = { value, schema, context in
      let baseResult = try await createMockValidator()(value, schema, context)
      if !baseResult.isValid { return baseResult }
      
      if case .string(let str) = value,
         case .object(let schemaObj) = schema,
         case .integer(let minLen) = schemaObj["minLength"],
         str.count < Int(minLen) {
        return JSONSchemaValidationResult(
          isValid: false,
          errors: [context.currentPath: [.stringTooShort(length: str.count, minimum: Int(minLen))]]
        )
      }
      
      return JSONSchemaValidationResult()
    }
    
    let result2 = try await validator.validateConditional(
      .string("hi"),
      schema: schema,
      context: context,
      validator: mockValidatorWithLength
    )
    #expect(!result2.isValid)
  }
  
  @Test("If condition fails, else branch validates")
  func ifElseValidation() async throws {
    let schema: [String: JSONValue] = [
      "if": .object(["type": .string("string")]),
      "else": .object(["type": .string("number")])
    ]
    
    let context = JSONSchemaValidationContext()
    
    // Number satisfies 'else' branch
    let result1 = try await validator.validateConditional(
      .number(42),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    #expect(result1.isValid)
    
    // Boolean doesn't satisfy 'else' branch
    let result2 = try await validator.validateConditional(
      .boolean(true),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    #expect(!result2.isValid)
  }
  
  @Test("If/Then/Else complete flow")
  func ifThenElseComplete() async throws {
    let schema: [String: JSONValue] = [
      "if": .object([
        "type": .string("object"),
        "required": .array([.string("country")])
      ]),
      "then": .object([
        "required": .array([.string("postal_code")])
      ]),
      "else": .object([
        "required": .array([.string("email")])
      ])
    ]
    
    let context = JSONSchemaValidationContext()
    
    // Object with country - needs postal_code
    let result1 = try await validator.validateConditional(
      .object(["country": .string("US"), "postal_code": .string("12345")]),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    #expect(result1.isValid)
    
    // Object with country but no postal_code - fails
    let result2 = try await validator.validateConditional(
      .object(["country": .string("US")]),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    #expect(!result2.isValid)
    
    // Object without country - needs email
    let result3 = try await validator.validateConditional(
      .object(["name": .string("John"), "email": .string("john@example.com")]),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    #expect(result3.isValid)
    
    // Object without country and without email - fails
    let result4 = try await validator.validateConditional(
      .object(["name": .string("John")]),
      schema: schema,
      context: context,
      validator: createMockValidator()
    )
    #expect(!result4.isValid)
  }
  
  // MARK: - Dependent Schemas Tests
  
  @Test("Dependent schemas validation")
  func dependentSchemas() async throws {
    let dependentSchemas: [String: JSONValue] = [
      "creditCard": .object([
        "required": .array([.string("billingAddress")])
      ])
    ]
    
    let context = JSONSchemaValidationContext()
    
    // Has creditCard and billingAddress - valid
    let result1 = try await validator.validateDependentSchemas(
      ["creditCard": .string("1234-5678"), "billingAddress": .string("123 Main St")],
      dependentSchemas: dependentSchemas,
      context: context,
      validator: createMockValidator()
    )
    #expect(result1.isValid)
    
    // Has creditCard but no billingAddress - invalid
    let result2 = try await validator.validateDependentSchemas(
      ["creditCard": .string("1234-5678")],
      dependentSchemas: dependentSchemas,
      context: context,
      validator: createMockValidator()
    )
    #expect(!result2.isValid)
    
    // No creditCard - dependent schema doesn't apply
    let result3 = try await validator.validateDependentSchemas(
      ["name": .string("John")],
      dependentSchemas: dependentSchemas,
      context: context,
      validator: createMockValidator()
    )
    #expect(result3.isValid)
  }
  
  // MARK: - Unevaluated Properties Tests
  
  @Test("Unevaluated properties with false schema")
  func unevaluatedPropertiesFalse() async throws {
    let obj: [String: JSONValue] = [
      "known": .string("value"),
      "unknown": .string("value")
    ]
    
    let context = JSONSchemaValidationContext()
    // Mark 'known' as evaluated
    context.markPropertyEvaluated("known")
    
    let result = try await validator.validateUnevaluatedProperties(
      obj,
      unevaluatedPropertiesSchema: .boolean(false),
      context: context,
      validator: createMockValidator()
    )
    
    #expect(!result.isValid)
    if case .unevaluatedPropertiesFound(let props) = result.errors[.root]?.first {
      #expect(props == ["unknown"])
    } else {
      Issue.record("Expected unevaluatedPropertiesFound error")
    }
  }
  
  @Test("Unevaluated properties with schema validation")
  func unevaluatedPropertiesWithSchema() async throws {
    let obj: [String: JSONValue] = [
      "known": .string("value"),
      "extra1": .string("string value"),
      "extra2": .number(42)
    ]
    
    let context = JSONSchemaValidationContext()
    context.markPropertyEvaluated("known")
    
    // Schema that only allows strings for unevaluated properties
    let unevaluatedSchema: JSONValue = .object(["type": .string("string")])
    
    let result = try await validator.validateUnevaluatedProperties(
      obj,
      unevaluatedPropertiesSchema: unevaluatedSchema,
      context: context,
      validator: createMockValidator()
    )
    
    // extra1 is valid (string), but extra2 is invalid (number)
    #expect(!result.isValid)
    
    // After validation, extra1 should be marked as evaluated
    let stillUnevaluated = context.getUnevaluatedProperties(for: obj)
    #expect(!stillUnevaluated.contains("extra1"))
  }
  
  // MARK: - Unevaluated Items Tests
  
  @Test("Unevaluated items with false schema")
  func unevaluatedItemsFalse() async throws {
    let arr: [JSONValue] = [
      .string("first"),
      .string("second"),
      .string("third")
    ]
    
    let context = JSONSchemaValidationContext()
    // Mark first two items as evaluated
    context.markItemEvaluated(0)
    context.markItemEvaluated(1)
    
    let result = try await validator.validateUnevaluatedItems(
      arr,
      unevaluatedItemsSchema: .boolean(false),
      context: context,
      validator: createMockValidator()
    )
    
    #expect(!result.isValid)
    if case .unevaluatedItemsFound(let indices) = result.errors[.root]?.first {
      #expect(indices == [2])
    } else {
      Issue.record("Expected unevaluatedItemsFound error")
    }
  }
  
  @Test("Unevaluated items with schema validation")
  func unevaluatedItemsWithSchema() async throws {
    let arr: [JSONValue] = [
      .string("first"),
      .string("second"),
      .number(3),
      .string("fourth")
    ]
    
    let context = JSONSchemaValidationContext()
    // Mark first two items as evaluated
    context.markItemEvaluated(0)
    context.markItemEvaluated(1)
    
    // Schema that only allows strings for unevaluated items
    let unevaluatedSchema: JSONValue = .object(["type": .string("string")])
    
    let result = try await validator.validateUnevaluatedItems(
      arr,
      unevaluatedItemsSchema: unevaluatedSchema,
      context: context,
      validator: createMockValidator()
    )
    
    // Item at index 3 is valid (string), but item at index 2 is invalid (number)
    #expect(!result.isValid)
    
    // After validation, item at index 3 should be marked as evaluated
    let stillUnevaluated = context.getUnevaluatedItems(for: arr)
    #expect(!stillUnevaluated.contains(3))
  }
  
  // MARK: - Contains Validation Tests
  
  @Test("Contains validation with minContains and maxContains")
  func containsValidation() async throws {
    let containsSchema: JSONValue = .object(["type": .string("string")])
    
    let arr: [JSONValue] = [
      .string("one"),
      .number(2),
      .string("three"),
      .boolean(false),
      .string("five")
    ]
    
    let context = JSONSchemaValidationContext()
    
    // Valid: has 3 strings, within min=2 and max=4
    let result1 = try await validator.validateContains(
      arr,
      containsSchema: containsSchema,
      minContains: 2,
      maxContains: 4,
      context: context,
      validator: createMockValidator()
    )
    #expect(result1.isValid)
    
    // Invalid: has 3 strings, but minContains=4
    let context2 = JSONSchemaValidationContext()
    let result2 = try await validator.validateContains(
      arr,
      containsSchema: containsSchema,
      minContains: 4,
      maxContains: nil,
      context: context2,
      validator: createMockValidator()
    )
    #expect(!result2.isValid)
    
    // Invalid: has 3 strings, but maxContains=2
    let context3 = JSONSchemaValidationContext()
    let result3 = try await validator.validateContains(
      arr,
      containsSchema: containsSchema,
      minContains: nil,
      maxContains: 2,
      context: context3,
      validator: createMockValidator()
    )
    #expect(!result3.isValid)
  }
  
  @Test("Contains validation marks evaluated items")
  func containsMarksEvaluated() async throws {
    let containsSchema: JSONValue = .object(["type": .string("string")])
    
    let arr: [JSONValue] = [
      .string("one"),
      .number(2),
      .string("three")
    ]
    
    let context = JSONSchemaValidationContext()
    
    let result = try await validator.validateContains(
      arr,
      containsSchema: containsSchema,
      minContains: nil,
      maxContains: nil,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(result.isValid)
    
    // Items at indices 0 and 2 should be marked as evaluated (they're strings)
    let unevaluated = context.getUnevaluatedItems(for: arr)
    #expect(!unevaluated.contains(0))
    #expect(unevaluated.contains(1))
    #expect(!unevaluated.contains(2))
  }
  
  // MARK: - Pattern Properties Tests
  
  @Test("Pattern properties validation")
  func patternProperties() async throws {
    let patternProps: [String: JSONValue] = [
      "^S_": .object(["type": .string("string")]),
      "^N_": .object(["type": .string("number")])
    ]
    
    let obj: [String: JSONValue] = [
      "S_name": .string("John"),
      "S_city": .string("NYC"),
      "N_age": .number(30),
      "N_count": .string("should be number"), // Invalid
      "other": .boolean(true)
    ]
    
    let context = JSONSchemaValidationContext()
    
    let result = try await validator.validatePatternProperties(
      obj,
      patternProperties: patternProps,
      context: context,
      validator: createMockValidator()
    )
    
    #expect(!result.isValid) // N_count has wrong type
    
    // Properties matching patterns should be marked as evaluated
    let unevaluated = context.getUnevaluatedProperties(for: obj)
    #expect(!unevaluated.contains("S_name"))
    #expect(!unevaluated.contains("S_city"))
    #expect(!unevaluated.contains("N_age"))
    #expect(unevaluated.contains("other")) // Doesn't match any pattern
  }
}