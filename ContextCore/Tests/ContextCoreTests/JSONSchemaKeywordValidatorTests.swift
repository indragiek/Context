// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite("JSON Schema Keyword Validator")
struct JSONSchemaKeywordValidatorTests {
  let validator = JSONSchemaKeywordValidator()
  
  // MARK: - Const Validation Tests
  
  @Test("Const validation with primitive values")
  func constPrimitiveValidation() {
    // String const
    let stringResult = validator.validateConst(.string("hello"), const: .string("hello"))
    #expect(stringResult.isValid)
    
    let stringFailResult = validator.validateConst(.string("world"), const: .string("hello"))
    #expect(!stringFailResult.isValid)
    
    // Number const
    let numberResult = validator.validateConst(.number(42.5), const: .number(42.5))
    #expect(numberResult.isValid)
    
    // Integer const
    let intResult = validator.validateConst(.integer(42), const: .integer(42))
    #expect(intResult.isValid)
    
    // Boolean const
    let boolResult = validator.validateConst(.boolean(true), const: .boolean(true))
    #expect(boolResult.isValid)
    
    // Null const
    let nullResult = validator.validateConst(.null, const: .null)
    #expect(nullResult.isValid)
  }
  
  @Test("Const validation with complex values")
  func constComplexValidation() {
    // Array const
    let arrayConst: JSONValue = .array([.string("a"), .number(1), .boolean(true)])
    let arrayResult = validator.validateConst(.array([.string("a"), .number(1), .boolean(true)]), const: arrayConst)
    #expect(arrayResult.isValid)
    
    // Different array order fails
    let arrayFailResult = validator.validateConst(.array([.number(1), .string("a"), .boolean(true)]), const: arrayConst)
    #expect(!arrayFailResult.isValid)
    
    // Object const
    let objectConst: JSONValue = .object(["name": .string("John"), "age": .integer(30)])
    let objectResult = validator.validateConst(.object(["age": .integer(30), "name": .string("John")]), const: objectConst)
    #expect(objectResult.isValid) // Order doesn't matter for objects
    
    // Missing property fails
    let objectFailResult = validator.validateConst(.object(["name": .string("John")]), const: objectConst)
    #expect(!objectFailResult.isValid)
  }
  
  @Test("Const validation with number/integer equivalence")
  func constNumberIntegerEquivalence() {
    // Integer const can match number value
    let result1 = validator.validateConst(.number(42.0), const: .integer(42))
    #expect(result1.isValid)
    
    // Number const can match integer value
    let result2 = validator.validateConst(.integer(42), const: .number(42.0))
    #expect(result2.isValid)
    
    // But not if the number has decimals
    let result3 = validator.validateConst(.number(42.5), const: .integer(42))
    #expect(!result3.isValid)
  }
  
  // MARK: - Enum Validation Tests
  
  @Test("Enum validation with primitive values")
  func enumPrimitiveValidation() {
    let enumValues: [JSONValue] = [.string("red"), .string("green"), .string("blue")]
    
    let validResult = validator.validateEnum(.string("green"), enumValues: enumValues)
    #expect(validResult.isValid)
    
    let invalidResult = validator.validateEnum(.string("yellow"), enumValues: enumValues)
    #expect(!invalidResult.isValid)
  }
  
  @Test("Enum validation with mixed types")
  func enumMixedTypesValidation() {
    let enumValues: [JSONValue] = [
      .string("hello"),
      .number(42),
      .boolean(true),
      .null,
      .array([.integer(1), .integer(2)])
    ]
    
    #expect(validator.validateEnum(.string("hello"), enumValues: enumValues).isValid)
    #expect(validator.validateEnum(.number(42), enumValues: enumValues).isValid)
    #expect(validator.validateEnum(.boolean(true), enumValues: enumValues).isValid)
    #expect(validator.validateEnum(.null, enumValues: enumValues).isValid)
    #expect(validator.validateEnum(.array([.integer(1), .integer(2)]), enumValues: enumValues).isValid)
    
    // Integer/number equivalence in enum
    #expect(validator.validateEnum(.integer(42), enumValues: enumValues).isValid)
    #expect(validator.validateEnum(.number(42.0), enumValues: enumValues).isValid)
    
    // Invalid values
    #expect(!validator.validateEnum(.string("world"), enumValues: enumValues).isValid)
    #expect(!validator.validateEnum(.boolean(false), enumValues: enumValues).isValid)
    #expect(!validator.validateEnum(.array([.integer(2), .integer(1)]), enumValues: enumValues).isValid)
  }
  
  // MARK: - Annotation Extraction Tests
  
  @Test("Extract annotations from schema")
  func extractAnnotations() {
    let schema: [String: JSONValue] = [
      "title": .string("User Profile"),
      "description": .string("A user profile object"),
      "examples": .array([
        .object(["name": .string("John"), "age": .integer(30)]),
        .object(["name": .string("Jane"), "age": .integer(25)])
      ]),
      "deprecated": .boolean(true),
      "readOnly": .boolean(true),
      "writeOnly": .boolean(false),
      "$comment": .string("This is a comment")
    ]
    
    let annotations = validator.extractAnnotations(from: schema)
    
    #expect(annotations.title == "User Profile")
    #expect(annotations.description == "A user profile object")
    #expect(annotations.examples?.count == 2)
    #expect(annotations.deprecated == true)
    #expect(annotations.readOnly == true)
    #expect(annotations.writeOnly == false)
    #expect(annotations.comment == "This is a comment")
  }
  
  @Test("Extract partial annotations")
  func extractPartialAnnotations() {
    let schema: [String: JSONValue] = [
      "title": .string("Simple Schema"),
      "type": .string("string") // Not an annotation
    ]
    
    let annotations = validator.extractAnnotations(from: schema)
    
    #expect(annotations.title == "Simple Schema")
    #expect(annotations.description == nil)
    #expect(annotations.examples == nil)
    #expect(annotations.deprecated == false)
    #expect(annotations.readOnly == false)
    #expect(annotations.writeOnly == false)
  }
  
  // MARK: - Metadata Extraction Tests
  
  @Test("Extract metadata from schema")
  func extractMetadata() {
    let schema: [String: JSONValue] = [
      "$id": .string("https://example.com/schemas/user"),
      "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
      "$anchor": .string("user"),
      "$dynamicAnchor": .string("meta"),
      "$vocabulary": .object([
        "https://json-schema.org/draft/2020-12/vocab/core": .boolean(true),
        "https://json-schema.org/draft/2020-12/vocab/validation": .boolean(true),
        "https://example.com/vocab/custom": .boolean(false)
      ])
    ]
    
    let metadata = validator.extractMetadata(from: schema)
    
    #expect(metadata.id == "https://example.com/schemas/user")
    #expect(metadata.schema == "https://json-schema.org/draft/2020-12/schema")
    #expect(metadata.anchor == "user")
    #expect(metadata.dynamicAnchor == "meta")
    #expect(metadata.vocabulary?["https://json-schema.org/draft/2020-12/vocab/core"] == true)
    #expect(metadata.vocabulary?["https://json-schema.org/draft/2020-12/vocab/validation"] == true)
    #expect(metadata.vocabulary?["https://example.com/vocab/custom"] == false)
  }
  
  // MARK: - Default Value Tests
  
  @Test("Extract default value")
  func extractDefaultValue() {
    let schemaWithDefault: [String: JSONValue] = [
      "type": .string("string"),
      "default": .string("Hello, World!")
    ]
    
    let defaultValue = validator.extractDefault(from: schemaWithDefault)
    #expect(defaultValue == .string("Hello, World!"))
    
    let schemaWithoutDefault: [String: JSONValue] = [
      "type": .string("string")
    ]
    
    let noDefaultValue = validator.extractDefault(from: schemaWithoutDefault)
    #expect(noDefaultValue == nil)
  }
  
  @Test("Extract complex default values")
  func extractComplexDefaultValues() {
    // Object default
    let objectDefault: JSONValue = .object(["name": .string("Anonymous"), "active": .boolean(true)])
    let schemaWithObjectDefault: [String: JSONValue] = [
      "type": .string("object"),
      "default": objectDefault
    ]
    
    #expect(validator.extractDefault(from: schemaWithObjectDefault) == objectDefault)
    
    // Array default
    let arrayDefault: JSONValue = .array([.string("option1"), .string("option2")])
    let schemaWithArrayDefault: [String: JSONValue] = [
      "type": .string("array"),
      "default": arrayDefault
    ]
    
    #expect(validator.extractDefault(from: schemaWithArrayDefault) == arrayDefault)
  }
  
  // MARK: - Pattern Properties Tests
  
  @Test("Extract pattern properties")
  func extractPatternProperties() {
    let schema: [String: JSONValue] = [
      "patternProperties": .object([
        "^S_": .object(["type": .string("string")]),
        "^I_": .object(["type": .string("integer")]),
        ".*_date$": .object(["type": .string("string"), "format": .string("date")])
      ])
    ]
    
    let patternProps = validator.extractPatternProperties(from: schema)
    #expect(patternProps?.count == 3)
    
    // Check that we got the patterns
    let patterns = patternProps?.map { $0.pattern } ?? []
    #expect(patterns.contains("^S_"))
    #expect(patterns.contains("^I_"))
    #expect(patterns.contains(".*_date$"))
  }
  
  @Test("Match pattern properties")
  func matchPatternProperties() async {
    let patternProperties: [(pattern: String, schema: JSONValue)] = [
      (pattern: "^S_", schema: .object(["type": .string("string")])),
      (pattern: "^I_", schema: .object(["type": .string("integer")])),
      (pattern: ".*_date$", schema: .object(["type": .string("string"), "format": .string("date")]))
    ]
    
    // Test matching
    let matches1 = await validator.matchPatternProperties(propertyName: "S_name", patternProperties: patternProperties)
    #expect(matches1.count == 1)
    #expect(matches1[0].pattern == "^S_")
    
    let matches2 = await validator.matchPatternProperties(propertyName: "I_count", patternProperties: patternProperties)
    #expect(matches2.count == 1)
    #expect(matches2[0].pattern == "^I_")
    
    let matches3 = await validator.matchPatternProperties(propertyName: "created_date", patternProperties: patternProperties)
    #expect(matches3.count == 1)
    #expect(matches3[0].pattern == ".*_date$")
    
    // Test non-matching
    let matches4 = await validator.matchPatternProperties(propertyName: "regular_property", patternProperties: patternProperties)
    #expect(matches4.isEmpty)
    
    // Test multiple matches
    let matches5 = await validator.matchPatternProperties(propertyName: "S_updated_date", patternProperties: patternProperties)
    #expect(matches5.count == 2) // Matches both "^S_" and ".*_date$"
  }
  
  // MARK: - Property Names Validation
  
  @Test("Validate property names")
  func validatePropertyNames() async throws {
    let propertyNamesSchema: JSONValue = .object([
      "type": .string("string"),
      "pattern": .string("^[a-zA-Z_][a-zA-Z0-9_]*$") // Valid identifier pattern
    ])
    
    // Mock validator that validates the property name as a string
    let mockValidator: (JSONValue, JSONValue) async throws -> JSONSchemaValidationResult = { value, schema in
      guard case .string(let str) = value,
            case .object(let schemaObj) = schema else {
        return JSONSchemaValidationResult(isValid: false, errors: [:])
      }
      
      // Simple pattern check
      if case .string(let pattern) = schemaObj["pattern"] {
        let isValid = await str.matchesPattern(pattern)
        return JSONSchemaValidationResult(isValid: isValid, errors: [:])
      }
      
      return JSONSchemaValidationResult()
    }
    
    // Valid property names
    let validNames: Set<String> = ["name", "firstName", "user_id", "_private"]
    let validResult = try await validator.validatePropertyNames(validNames, schema: propertyNamesSchema, validator: mockValidator)
    #expect(validResult.isValid)
    
    // Invalid property names
    let invalidNames: Set<String> = ["123invalid", "has-dash", "has space"]
    let invalidResult = try await validator.validatePropertyNames(invalidNames, schema: propertyNamesSchema, validator: mockValidator)
    #expect(!invalidResult.isValid)
  }
}