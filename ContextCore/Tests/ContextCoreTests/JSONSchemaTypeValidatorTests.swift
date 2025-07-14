// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite("JSON Schema Type Validator")
struct JSONSchemaTypeValidatorTests {
  let validator = JSONSchemaTypeValidator()
  
  // MARK: - Type Matching Tests
  
  @Test("Type matching")
  func typeMatching() {
    #expect(validator.matchesType(.null, type: "null"))
    #expect(validator.matchesType(.boolean(true), type: "boolean"))
    #expect(validator.matchesType(.string("test"), type: "string"))
    #expect(validator.matchesType(.number(3.14), type: "number"))
    #expect(validator.matchesType(.integer(42), type: "integer"))
    #expect(validator.matchesType(.array([]), type: "array"))
    #expect(validator.matchesType(.object([:]), type: "object"))
    
    // Integer as number
    #expect(validator.matchesType(.integer(42), type: "number"))
    
    // Number as integer (only if whole number)
    #expect(validator.matchesType(.number(42.0), type: "integer"))
    #expect(!validator.matchesType(.number(42.5), type: "integer"))
    
    // Type mismatches
    #expect(!validator.matchesType(.string("test"), type: "number"))
    #expect(!validator.matchesType(.boolean(true), type: "string"))
  }
  
  @Test("Multiple types validation")
  func multipleTypes() {
    let types = ["string", "number", "null"]
    
    #expect(validator.validateType(.string("test"), types: types))
    #expect(validator.validateType(.number(42), types: types))
    #expect(validator.validateType(.null, types: types))
    #expect(!validator.validateType(.boolean(true), types: types))
  }
  
  // MARK: - Number Validation Tests
  
  @Test("Number minimum constraint")
  func numberMinimum() {
    let schema: [String: JSONValue] = ["minimum": .number(5.0)]
    
    #expect(validator.validateNumber(5.0, schema: schema).isValid)
    #expect(validator.validateNumber(10.0, schema: schema).isValid)
    #expect(!validator.validateNumber(4.9, schema: schema).isValid)
  }
  
  @Test("Number exclusive minimum constraint")
  func numberExclusiveMinimum() {
    let schema: [String: JSONValue] = ["exclusiveMinimum": .number(5.0)]
    
    #expect(validator.validateNumber(5.1, schema: schema).isValid)
    #expect(!validator.validateNumber(5.0, schema: schema).isValid)
    #expect(!validator.validateNumber(4.9, schema: schema).isValid)
  }
  
  @Test("Number maximum constraint")
  func numberMaximum() {
    let schema: [String: JSONValue] = ["maximum": .number(10.0)]
    
    #expect(validator.validateNumber(10.0, schema: schema).isValid)
    #expect(validator.validateNumber(5.0, schema: schema).isValid)
    #expect(!validator.validateNumber(10.1, schema: schema).isValid)
  }
  
  @Test("Number exclusive maximum constraint")
  func numberExclusiveMaximum() {
    let schema: [String: JSONValue] = ["exclusiveMaximum": .number(10.0)]
    
    #expect(validator.validateNumber(9.9, schema: schema).isValid)
    #expect(!validator.validateNumber(10.0, schema: schema).isValid)
    #expect(!validator.validateNumber(10.1, schema: schema).isValid)
  }
  
  @Test("Number multiple of constraint")
  func numberMultipleOf() {
    let schema: [String: JSONValue] = ["multipleOf": .number(3.0)]
    
    #expect(validator.validateNumber(0, schema: schema).isValid)
    #expect(validator.validateNumber(3.0, schema: schema).isValid)
    #expect(validator.validateNumber(6.0, schema: schema).isValid)
    #expect(validator.validateNumber(-9.0, schema: schema).isValid)
    #expect(!validator.validateNumber(3.5, schema: schema).isValid)
    #expect(!validator.validateNumber(7.0, schema: schema).isValid)
  }
  
  @Test("Number combined constraints")
  func numberCombinedConstraints() {
    let schema: [String: JSONValue] = [
      "minimum": .number(0),
      "maximum": .number(100),
      "multipleOf": .number(5)
    ]
    
    #expect(validator.validateNumber(0, schema: schema).isValid)
    #expect(validator.validateNumber(50, schema: schema).isValid)
    #expect(validator.validateNumber(100, schema: schema).isValid)
    #expect(!validator.validateNumber(-5, schema: schema).isValid)
    #expect(!validator.validateNumber(105, schema: schema).isValid)
    #expect(!validator.validateNumber(52, schema: schema).isValid)
  }
  
  // MARK: - Integer Validation Tests
  
  @Test("Integer validation")
  func integerValidation() {
    let schema: [String: JSONValue] = [
      "minimum": .integer(10),
      "maximum": .integer(20)
    ]
    
    #expect(validator.validateInteger(15, schema: schema).isValid)
    #expect(validator.validateInteger(10, schema: schema).isValid)
    #expect(validator.validateInteger(20, schema: schema).isValid)
    #expect(!validator.validateInteger(9, schema: schema).isValid)
    #expect(!validator.validateInteger(21, schema: schema).isValid)
  }
  
  // MARK: - String Validation Tests
  
  @Test("String minimum length")
  func stringMinLength() async {
    let schema: [String: JSONValue] = ["minLength": .integer(3)]
    
    let result1 = await validator.validateString("abc", schema: schema)
    #expect(result1.isValid)
    
    let result2 = await validator.validateString("abcd", schema: schema)
    #expect(result2.isValid)
    
    let result3 = await validator.validateString("ab", schema: schema)
    #expect(!result3.isValid)
    
    // Test empty string
    let result4 = await validator.validateString("", schema: schema)
    #expect(!result4.isValid)
  }
  
  @Test("String maximum length")
  func stringMaxLength() async {
    let schema: [String: JSONValue] = ["maxLength": .integer(5)]
    
    let result1 = await validator.validateString("hello", schema: schema)
    #expect(result1.isValid)
    
    let result2 = await validator.validateString("hi", schema: schema)
    #expect(result2.isValid)
    
    let result3 = await validator.validateString("hello!", schema: schema)
    #expect(!result3.isValid)
  }
  
  @Test("String pattern matching")
  func stringPattern() async {
    let schema: [String: JSONValue] = ["pattern": .string("^[a-z]+$")]
    
    let result1 = await validator.validateString("hello", schema: schema)
    #expect(result1.isValid)
    
    let result2 = await validator.validateString("Hello", schema: schema)
    #expect(!result2.isValid)
    
    let result3 = await validator.validateString("hello123", schema: schema)
    #expect(!result3.isValid)
  }
  
  @Test("String format validation")
  func stringFormat() async {
    // Email format
    let emailSchema: [String: JSONValue] = ["format": .string("email")]
    
    let result1 = await validator.validateString("test@example.com", schema: emailSchema)
    #expect(result1.isValid)
    
    let result2 = await validator.validateString("invalid-email", schema: emailSchema)
    #expect(!result2.isValid)
    
    // Date format
    let dateSchema: [String: JSONValue] = ["format": .string("date")]
    
    let result3 = await validator.validateString("2025-01-15", schema: dateSchema)
    #expect(result3.isValid)
    
    let result4 = await validator.validateString("2025-13-01", schema: dateSchema)
    #expect(!result4.isValid)
  }
  
  // MARK: - Array Validation Tests
  
  @Test("Array minimum items")
  func arrayMinItems() {
    let schema: [String: JSONValue] = ["minItems": .integer(2)]
    let context = JSONSchemaValidationContext()
    
    let result1 = validator.validateArray([.string("a"), .string("b")], schema: schema, context: context)
    #expect(result1.isValid)
    
    let result2 = validator.validateArray([.string("a")], schema: schema, context: context)
    #expect(!result2.isValid)
    
    let result3 = validator.validateArray([], schema: schema, context: context)
    #expect(!result3.isValid)
  }
  
  @Test("Array maximum items")
  func arrayMaxItems() {
    let schema: [String: JSONValue] = ["maxItems": .integer(3)]
    let context = JSONSchemaValidationContext()
    
    let result1 = validator.validateArray([.string("a"), .string("b")], schema: schema, context: context)
    #expect(result1.isValid)
    
    let result2 = validator.validateArray([.string("a"), .string("b"), .string("c"), .string("d")], schema: schema, context: context)
    #expect(!result2.isValid)
  }
  
  @Test("Array unique items")
  func arrayUniqueItems() {
    let schema: [String: JSONValue] = ["uniqueItems": .boolean(true)]
    let context = JSONSchemaValidationContext()
    
    let result1 = validator.validateArray([.string("a"), .string("b"), .string("c")], schema: schema, context: context)
    #expect(result1.isValid)
    
    let result2 = validator.validateArray([.string("a"), .string("b"), .string("a")], schema: schema, context: context)
    #expect(!result2.isValid)
    
    // Test with different types but same values
    let result3 = validator.validateArray([.integer(42), .number(42.0)], schema: schema, context: context)
    #expect(result3.isValid) // Different types, so considered unique
    
    // Test with objects
    let obj1: JSONValue = .object(["a": .string("1"), "b": .string("2")])
    let obj2: JSONValue = .object(["b": .string("2"), "a": .string("1")])
    let result4 = validator.validateArray([obj1, obj2], schema: schema, context: context)
    #expect(!result4.isValid) // Same object content, different key order
  }
  
  // MARK: - Object Validation Tests
  
  @Test("Object minimum properties")
  func objectMinProperties() async {
    let schema: [String: JSONValue] = ["minProperties": .integer(2)]
    let context = JSONSchemaValidationContext()
    
    let result1 = await validator.validateObject(["a": .string("1"), "b": .string("2")], schema: schema, context: context)
    #expect(result1.isValid)
    
    let result2 = await validator.validateObject(["a": .string("1")], schema: schema, context: context)
    #expect(!result2.isValid)
    
    let result3 = await validator.validateObject([:], schema: schema, context: context)
    #expect(!result3.isValid)
  }
  
  @Test("Object maximum properties")
  func objectMaxProperties() async {
    let schema: [String: JSONValue] = ["maxProperties": .integer(2)]
    let context = JSONSchemaValidationContext()
    
    let result1 = await validator.validateObject(["a": .string("1"), "b": .string("2")], schema: schema, context: context)
    #expect(result1.isValid)
    
    let result2 = await validator.validateObject(["a": .string("1"), "b": .string("2"), "c": .string("3")], schema: schema, context: context)
    #expect(!result2.isValid)
  }
  
  @Test("Object required properties")
  func objectRequired() async {
    let schema: [String: JSONValue] = [
      "required": .array([.string("name"), .string("age")])
    ]
    let context = JSONSchemaValidationContext()
    
    let result1 = await validator.validateObject(["name": .string("John"), "age": .integer(30)], schema: schema, context: context)
    #expect(result1.isValid)
    
    let result2 = await validator.validateObject(["name": .string("John")], schema: schema, context: context)
    #expect(!result2.isValid)
    
    let result3 = await validator.validateObject(["age": .integer(30)], schema: schema, context: context)
    #expect(!result3.isValid)
  }
  
  @Test("Object dependent required properties")
  func objectDependentRequired() async {
    let schema: [String: JSONValue] = [
      "dependentRequired": .object([
        "creditCard": .array([.string("billingAddress"), .string("cvv")])
      ])
    ]
    let context = JSONSchemaValidationContext()
    
    // Valid: has creditCard and all dependent properties
    let result1 = await validator.validateObject([
      "creditCard": .string("1234-5678-9012-3456"),
      "billingAddress": .string("123 Main St"),
      "cvv": .string("123")
    ], schema: schema, context: context)
    #expect(result1.isValid)
    
    // Valid: no creditCard, so dependencies don't apply
    let result2 = await validator.validateObject([
      "name": .string("John")
    ], schema: schema, context: context)
    #expect(result2.isValid)
    
    // Invalid: has creditCard but missing billingAddress
    let result3 = await validator.validateObject([
      "creditCard": .string("1234-5678-9012-3456"),
      "cvv": .string("123")
    ], schema: schema, context: context)
    #expect(!result3.isValid)
  }
  
  // MARK: - ReDoS Protection Tests
  
  @Test("Pattern matching with timeout protection")
  func patternMatchingTimeout() async {
    // Test that regex matching respects timeout
    let dangerousPattern = "(a+)+"
    let longString = String(repeating: "a", count: 100) + "!"
    
    let schema: [String: JSONValue] = ["pattern": .string(dangerousPattern)]
    let context = JSONSchemaValidationContext(
      options: JSONSchemaValidationOptions(maxRegexEvaluationTime: 0.1) // 100ms timeout
    )
    
    let result = await validator.validateString(longString, schema: schema, context: context)
    // Should fail validation due to pattern mismatch or timeout
    #expect(!result.isValid)
  }
}