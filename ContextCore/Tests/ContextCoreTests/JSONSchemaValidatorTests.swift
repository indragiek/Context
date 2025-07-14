// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite("JSON Schema Validator", .timeLimit(.minutes(2)))
struct JSONSchemaValidatorTests {
  
  // MARK: - Validation Options Tests
  
  @Test("Format validation can be disabled")
  func formatValidationToggle() async throws {
    let validator = JSONSchemaValidator()
    let schema: JSONValue = .object([
      "type": .string("string"),
      "format": .string("email")
    ])
    
    // With format validation enabled (default)
    let enabledOptions = JSONSchemaValidationOptions(validateFormats: true)
    let result1 = try await validator.validate(
      .string("not-an-email"), 
      against: schema,
      options: enabledOptions
    )
    #expect(!result1.isValid)
    
    // With format validation disabled
    let disabledOptions = JSONSchemaValidationOptions(validateFormats: false)
    let result2 = try await validator.validate(
      .string("not-an-email"), 
      against: schema,
      options: disabledOptions
    )
    #expect(result2.isValid)
  }
  
  @Test("Vocabulary enforcement")
  func vocabularyEnforcement() async throws {
    let validator = JSONSchemaValidator()
    let schema: JSONValue = .object([
      "$vocabulary": .object([
        "https://json-schema.org/draft/2020-12/vocab/core": .boolean(true),
        "https://json-schema.org/draft/2020-12/vocab/validation": .boolean(true)
        // Notably missing applicator vocabulary
      ]),
      "type": .string("object"),
      "properties": .object([  // This is from applicator vocabulary
        "name": .object(["type": .string("string")])
      ])
    ])
    
    // Without vocabulary enforcement
    let permissiveOptions = JSONSchemaValidationOptions(enforceVocabularies: false)
    let result1 = try await validator.validate(
      .object(["name": .string("test")]), 
      against: schema,
      options: permissiveOptions
    )
    #expect(result1.isValid)
    
    // With vocabulary enforcement
    let strictOptions = JSONSchemaValidationOptions(enforceVocabularies: true)
    let result2 = try await validator.validate(
      .object(["name": .string("test")]), 
      against: schema,
      options: strictOptions
    )
    #expect(!result2.isValid)
    #expect(result2.errors[.root]?.contains { 
      if case .unknownKeyword(let keyword, let vocab) = $0 {
        return keyword == "properties" && vocab == "https://json-schema.org/draft/2020-12/vocab/applicator"
      }
      return false
    } == true)
  }
  
  @Test("Annotation collection")
  func annotationCollection() async throws {
    let validator = JSONSchemaValidator()
    let schema: JSONValue = .object([
      "title": .string("Person Schema"),
      "description": .string("A schema for a person"),
      "type": .string("object"),
      "properties": .object([
        "name": .object([
          "type": .string("string"),
          "title": .string("Full Name"),
          "description": .string("The person's full name"),
          "format": .string("email")  // Will be collected as annotation when not validating
        ])
      ])
    ])
    
    let options = JSONSchemaValidationOptions(
      validateFormats: false,  // Format becomes annotation
      collectAnnotations: true
    )
    
    let result = try await validator.validate(
      .object(["name": .string("John Doe")]), 
      against: schema,
      options: options
    )
    
    #expect(result.isValid)
    #expect(result.annotations[.root]?["title"] == .string("Person Schema"))
    #expect(result.annotations[.root]?["description"] == .string("A schema for a person"))
    #expect(result.annotations[JSONSchemaValidationPath(components: [.root, .property("name")])]?["title"] == .string("Full Name"))
    #expect(result.annotations[JSONSchemaValidationPath(components: [.root, .property("name")])]?["format"] == .string("email"))
  }
  
  // MARK: - Boolean Schema Tests
  
  @Test("Boolean schema validation")
  func booleanSchemaValidation() async throws {
    let validator = JSONSchemaValidator()
    
    // true schema allows any value
    let trueResult = try await validator.validate(.string("anything"), against: .boolean(true))
    #expect(trueResult.isValid)
    
    // false schema allows no value
    let falseResult = try await validator.validate(.string("anything"), against: .boolean(false))
    #expect(!falseResult.isValid)
    #expect(falseResult.errors[.root]?.contains { $0 == .schemaValidationDisabled } == true)
  }
  
  // MARK: - Type Validation Tests
  
  @Test("Basic type validation")
  func basicTypeValidation() async throws {
    let validator = JSONSchemaValidator()
    
    // Single type
    let stringSchema: JSONValue = .object(["type": .string("string")])
    let stringResult = try await validator.validate(.string("hello"), against: stringSchema)
    #expect(stringResult.isValid)
    
    let stringFailResult = try await validator.validate(.number(42), against: stringSchema)
    #expect(!stringFailResult.isValid)
    
    // Multiple types
    let multiTypeSchema: JSONValue = .object(["type": .array([.string("string"), .string("number")])])
    let multiResult1 = try await validator.validate(.string("hello"), against: multiTypeSchema)
    #expect(multiResult1.isValid)
    
    let multiResult2 = try await validator.validate(.number(42), against: multiTypeSchema)
    #expect(multiResult2.isValid)
    
    let multiResult3 = try await validator.validate(.boolean(true), against: multiTypeSchema)
    #expect(!multiResult3.isValid)
  }
  
  // MARK: - Const and Enum Tests
  
  @Test("Const validation")
  func constValidation() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "const": .string("exactValue")
    ])
    
    let validResult = try await validator.validate(.string("exactValue"), against: schema)
    #expect(validResult.isValid)
    
    let invalidResult = try await validator.validate(.string("wrongValue"), against: schema)
    #expect(!invalidResult.isValid)
  }
  
  @Test("Enum validation")
  func enumValidation() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "enum": .array([.string("red"), .string("green"), .string("blue")])
    ])
    
    let validResult = try await validator.validate(.string("green"), against: schema)
    #expect(validResult.isValid)
    
    let invalidResult = try await validator.validate(.string("yellow"), against: schema)
    #expect(!invalidResult.isValid)
  }
  
  // MARK: - Number Validation Tests
  
  @Test("Number constraints validation")
  func numberConstraints() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("number"),
      "minimum": .number(0),
      "maximum": .number(100),
      "multipleOf": .number(5)
    ])
    
    let validResult = try await validator.validate(.number(50), against: schema)
    #expect(validResult.isValid)
    
    let tooSmallResult = try await validator.validate(.number(-5), against: schema)
    #expect(!tooSmallResult.isValid)
    
    let notMultipleResult = try await validator.validate(.number(52), against: schema)
    #expect(!notMultipleResult.isValid)
  }
  
  // MARK: - String Validation Tests
  
  @Test("String constraints validation")
  func stringConstraints() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("string"),
      "minLength": .integer(3),
      "maxLength": .integer(10),
      "pattern": .string("^[a-z]+$")
    ])
    
    let validResult = try await validator.validate(.string("hello"), against: schema)
    #expect(validResult.isValid)
    
    let tooShortResult = try await validator.validate(.string("hi"), against: schema)
    #expect(!tooShortResult.isValid)
    
    let invalidPatternResult = try await validator.validate(.string("Hello"), against: schema)
    #expect(!invalidPatternResult.isValid)
  }
  
  @Test("String format validation")
  func stringFormat() async throws {
    let validator = JSONSchemaValidator()
    
    let emailSchema: JSONValue = .object([
      "type": .string("string"),
      "format": .string("email")
    ])
    
    let validEmail = try await validator.validate(.string("test@example.com"), against: emailSchema)
    #expect(validEmail.isValid)
    
    let invalidEmail = try await validator.validate(.string("not-an-email"), against: emailSchema)
    #expect(!invalidEmail.isValid)
  }
  
  // MARK: - Array Validation Tests
  
  @Test("Array items validation")
  func arrayItems() async throws {
    let validator = JSONSchemaValidator()
    
    // Uniform items
    let uniformSchema: JSONValue = .object([
      "type": .string("array"),
      "items": .object(["type": .string("string")])
    ])
    
    let validUniform = try await validator.validate(
      .array([.string("a"), .string("b"), .string("c")]),
      against: uniformSchema
    )
    #expect(validUniform.isValid)
    
    let invalidUniform = try await validator.validate(
      .array([.string("a"), .number(2), .string("c")]),
      against: uniformSchema
    )
    #expect(!invalidUniform.isValid)
  }
  
  @Test("Array tuple validation (prefixItems)")
  func arrayTupleValidation() async throws {
    let validator = JSONSchemaValidator()
    
    let tupleSchema: JSONValue = .object([
      "type": .string("array"),
      "prefixItems": .array([
        .object(["type": .string("string")]),
        .object(["type": .string("number")]),
        .object(["type": .string("boolean")])
      ]),
      "additionalItems": .boolean(false)
    ])
    
    // Valid tuple
    let validTuple = try await validator.validate(
      .array([.string("hello"), .number(42), .boolean(true)]),
      against: tupleSchema
    )
    #expect(validTuple.isValid)
    
    // Too many items
    let tooManyItems = try await validator.validate(
      .array([.string("hello"), .number(42), .boolean(true), .string("extra")]),
      against: tupleSchema
    )
    #expect(!tooManyItems.isValid)
    
    // Wrong type at position
    let wrongType = try await validator.validate(
      .array([.string("hello"), .string("not a number"), .boolean(true)]),
      against: tupleSchema
    )
    #expect(!wrongType.isValid)
  }
  
  @Test("Array contains validation")
  func arrayContains() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("array"),
      "contains": .object(["type": .string("string")]),
      "minContains": .integer(2),
      "maxContains": .integer(4)
    ])
    
    // Valid: has 3 strings
    let valid = try await validator.validate(
      .array([.string("a"), .number(1), .string("b"), .string("c"), .boolean(true)]),
      against: schema
    )
    #expect(valid.isValid)
    
    // Invalid: only 1 string
    let tooFew = try await validator.validate(
      .array([.string("a"), .number(1), .number(2)]),
      against: schema
    )
    #expect(!tooFew.isValid)
  }
  
  // MARK: - Object Validation Tests
  
  @Test("Object properties validation")
  func objectProperties() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string")]),
        "age": .object(["type": .string("integer")])
      ]),
      "required": .array([.string("name")])
    ])
    
    // Valid object
    let valid = try await validator.validate(
      .object(["name": .string("John"), "age": .integer(30)]),
      against: schema
    )
    #expect(valid.isValid)
    
    // Missing required property
    let missingRequired = try await validator.validate(
      .object(["age": .integer(30)]),
      against: schema
    )
    #expect(!missingRequired.isValid)
    
    // Wrong type for property
    let wrongType = try await validator.validate(
      .object(["name": .string("John"), "age": .string("thirty")]),
      against: schema
    )
    #expect(!wrongType.isValid)
  }
  
  @Test("Object additionalProperties validation")
  func objectAdditionalProperties() async throws {
    let validator = JSONSchemaValidator()
    
    // No additional properties allowed
    let noAdditionalSchema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string")])
      ]),
      "additionalProperties": .boolean(false)
    ])
    
    let invalidAdditional = try await validator.validate(
      .object(["name": .string("John"), "extra": .string("not allowed")]),
      against: noAdditionalSchema
    )
    #expect(!invalidAdditional.isValid)
    
    // Additional properties with schema
    let additionalSchema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string")])
      ]),
      "additionalProperties": .object(["type": .string("number")])
    ])
    
    let validAdditional = try await validator.validate(
      .object(["name": .string("John"), "extra": .number(42)]),
      against: additionalSchema
    )
    #expect(validAdditional.isValid)
    
    let invalidAdditionalType = try await validator.validate(
      .object(["name": .string("John"), "extra": .string("not a number")]),
      against: additionalSchema
    )
    #expect(!invalidAdditionalType.isValid)
  }
  
  // MARK: - Composition Tests
  
  @Test("AllOf validation")
  func allOfValidation() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "allOf": .array([
        .object(["type": .string("object"), "properties": .object(["name": .object(["type": .string("string")])])]),
        .object(["properties": .object(["age": .object(["type": .string("number")])])]),
        .object(["required": .array([.string("name")])])
      ])
    ])
    
    let valid = try await validator.validate(
      .object(["name": .string("John"), "age": .number(30)]),
      against: schema
    )
    #expect(valid.isValid)
    
    let missingRequired = try await validator.validate(
      .object(["age": .number(30)]),
      against: schema
    )
    #expect(!missingRequired.isValid)
  }
  
  @Test("OneOf validation")
  func oneOfValidation() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "oneOf": .array([
        .object(["type": .string("string")]),
        .object(["type": .string("number")]),
        .object(["type": .string("boolean")])
      ])
    ])
    
    // Valid: matches exactly one schema
    let valid = try await validator.validate(.string("hello"), against: schema)
    #expect(valid.isValid)
    
    // Invalid: matches none
    let matchesNone = try await validator.validate(.array([]), against: schema)
    #expect(!matchesNone.isValid)
  }
  
  // MARK: - Conditional Tests
  
  @Test("If/Then/Else validation")
  func ifThenElseValidation() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("object"),
      "if": .object([
        "properties": .object(["country": .object(["const": .string("US")])])
      ]),
      "then": .object([
        "required": .array([.string("zipCode")])
      ]),
      "else": .object([
        "required": .array([.string("postalCode")])
      ])
    ])
    
    // US address needs zipCode
    let usValid = try await validator.validate(
      .object(["country": .string("US"), "zipCode": .string("12345")]),
      against: schema
    )
    #expect(usValid.isValid)
    
    let usInvalid = try await validator.validate(
      .object(["country": .string("US"), "postalCode": .string("12345")]),
      against: schema
    )
    #expect(!usInvalid.isValid)
    
    // Non-US address needs postalCode
    let nonUsValid = try await validator.validate(
      .object(["country": .string("CA"), "postalCode": .string("K1A 0B1")]),
      against: schema
    )
    #expect(nonUsValid.isValid)
  }
  
  // MARK: - Reference Tests
  
  @Test("Internal reference resolution")
  func internalReferences() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "$defs": .object([
        "positiveInteger": .object([
          "type": .string("integer"),
          "minimum": .integer(1)
        ])
      ]),
      "type": .string("object"),
      "properties": .object([
        "age": .object(["$ref": .string("#/$defs/positiveInteger")])
      ])
    ])
    
    validator.setRootSchema(schema)
    
    let valid = try await validator.validate(
      .object(["age": .integer(25)]),
      against: schema
    )
    #expect(valid.isValid)
    
    let invalid = try await validator.validate(
      .object(["age": .integer(0)]),
      against: schema
    )
    #expect(!invalid.isValid)
  }
  
  // MARK: - Unevaluated Properties/Items Tests
  
  @Test("Unevaluated properties validation")
  func unevaluatedProperties() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string")])
      ]),
      "unevaluatedProperties": .boolean(false)
    ])
    
    // All properties are evaluated
    let valid = try await validator.validate(
      .object(["name": .string("John")]),
      against: schema
    )
    #expect(valid.isValid)
    
    // Has unevaluated property
    let invalid = try await validator.validate(
      .object(["name": .string("John"), "extra": .string("value")]),
      against: schema
    )
    #expect(!invalid.isValid)
  }
  
  // MARK: - Complex Schema Tests
  
  @Test("Complex nested schema validation")
  func complexNestedSchema() async throws {
    let validator = JSONSchemaValidator()
    
    let personSchema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string"), "minLength": .integer(1)]),
        "age": .object(["type": .string("integer"), "minimum": .integer(0), "maximum": .integer(150)]),
        "email": .object(["type": .string("string"), "format": .string("email")]),
        "address": .object([
          "type": .string("object"),
          "properties": .object([
            "street": .object(["type": .string("string")]),
            "city": .object(["type": .string("string")]),
            "zipCode": .object(["type": .string("string"), "pattern": .string("^\\d{5}$")])
          ]),
          "required": .array([.string("street"), .string("city")])
        ])
      ]),
      "required": .array([.string("name"), .string("email")])
    ])
    
    let validPerson: JSONValue = .object([
      "name": .string("John Doe"),
      "age": .integer(30),
      "email": .string("john@example.com"),
      "address": .object([
        "street": .string("123 Main St"),
        "city": .string("New York"),
        "zipCode": .string("10001")
      ])
    ])
    
    let result = try await validator.validate(validPerson, against: personSchema)
    #expect(result.isValid)
    
    // Invalid: missing required city in address
    let invalidPerson: JSONValue = .object([
      "name": .string("John Doe"),
      "email": .string("john@example.com"),
      "address": .object([
        "street": .string("123 Main St"),
        "zipCode": .string("10001")
      ])
    ])
    
    let invalidResult = try await validator.validate(invalidPerson, against: personSchema)
    #expect(!invalidResult.isValid)
  }
  
  // MARK: - Content Schema Tests
  
  @Test("Content schema validation")
  func contentSchemaValidation() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("string"),
      "contentMediaType": .string("application/json"),
      "contentSchema": .object([
        "type": .string("object"),
        "properties": .object([
          "name": .object(["type": .string("string")])
        ]),
        "required": .array([.string("name")])
      ])
    ])
    
    // Valid JSON content
    let validResult = try await validator.validate(
      .string("{\"name\": \"John\"}"),
      against: schema
    )
    #expect(validResult.isValid)
    
    // Invalid JSON content (missing required property)
    let invalidResult = try await validator.validate(
      .string("{\"age\": 30}"),
      against: schema
    )
    #expect(!invalidResult.isValid)
    
    // Not valid JSON
    let notJsonResult = try await validator.validate(
      .string("not json"),
      against: schema
    )
    #expect(notJsonResult.isValid) // contentSchema is ignored if content isn't valid JSON
  }
  
  // MARK: - Dialect Support Tests
  
  @Test("Modern dialect items behavior")
  func modernDialectItems() async throws {
    let validator = JSONSchemaValidator()
    
    // Modern 2020-12 schema with prefixItems and items
    let modernSchema: JSONValue = .object([
      "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
      "type": .string("array"),
      "prefixItems": .array([
        .object(["type": .string("string")]),
        .object(["type": .string("number")])
      ]),
      "items": .object(["type": .string("boolean")])  // Applies after prefixItems
    ])
    
    // Valid: string, number, then booleans
    let valid = try await validator.validate(
      .array([.string("hello"), .number(42), .boolean(true), .boolean(false)]),
      against: modernSchema
    )
    #expect(valid.isValid)
    
    // Invalid: wrong type after prefixItems
    let invalid = try await validator.validate(
      .array([.string("hello"), .number(42), .string("not boolean")]),
      against: modernSchema
    )
    #expect(!invalid.isValid)
  }
  
  @Test("Legacy dialect items behavior")
  func legacyDialectItems() async throws {
    let validator = JSONSchemaValidator()
    
    // Legacy draft-07 schema with tuple validation
    let legacySchema: JSONValue = .object([
      "$schema": .string("http://json-schema.org/draft-07/schema#"),
      "type": .string("array"),
      "items": .array([
        .object(["type": .string("string")]),
        .object(["type": .string("number")])
      ]),
      "additionalItems": .object(["type": .string("boolean")])
    ])
    
    // Valid: string, number, then booleans
    let valid = try await validator.validate(
      .array([.string("hello"), .number(42), .boolean(true)]),
      against: legacySchema
    )
    #expect(valid.isValid)
    
    // Invalid: wrong type in additionalItems
    let invalid = try await validator.validate(
      .array([.string("hello"), .number(42), .string("not boolean")]),
      against: legacySchema
    )
    #expect(!invalid.isValid)
  }
  
  // MARK: - Dynamic Reference Tests
  
  @Test("Dynamic reference resolution")
  func dynamicReferenceResolution() async throws {
    let validator = JSONSchemaValidator()
    
    // Schema with dynamic anchors
    let schema: JSONValue = .object([
      "$id": .string("https://example.com/tree"),
      "$dynamicAnchor": .string("node"),
      "type": .string("object"),
      "properties": .object([
        "data": .object(["type": .string("string")]),
        "children": .object([
          "type": .string("array"),
          "items": .object([
            "$dynamicRef": .string("#node")  // References the dynamic anchor
          ])
        ])
      ])
    ])
    
    validator.setRootSchema(schema)
    
    // Valid recursive structure
    let valid = try await validator.validate(
      .object([
        "data": .string("root"),
        "children": .array([
          .object([
            "data": .string("child1"),
            "children": .array([])
          ]),
          .object([
            "data": .string("child2"),
            "children": .array([
              .object([
                "data": .string("grandchild"),
                "children": .array([])
              ])
            ])
          ])
        ])
      ]),
      against: schema
    )
    #expect(valid.isValid)
  }
  
  // MARK: - Additional Properties Behavior Tests
  
  @Test("Additional properties default behavior")
  func additionalPropertiesDefault() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string")])
      ])
      // No additionalProperties specified - defaults to true
    ])
    
    // Additional properties should be allowed by default
    let result = try await validator.validate(
      .object([
        "name": .string("John"),
        "age": .integer(30),
        "extra": .string("allowed")
      ]),
      against: schema
    )
    #expect(result.isValid)
  }
  
  @Test("Additional properties with unevaluated properties")
  func additionalPropertiesWithUnevaluated() async throws {
    let validator = JSONSchemaValidator()
    
    let schema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string")])
      ]),
      // additionalProperties not specified (defaults to true)
      "unevaluatedProperties": .boolean(false)
    ])
    
    // Even though additionalProperties defaults to true,
    // unevaluatedProperties: false should catch extra properties
    let result = try await validator.validate(
      .object([
        "name": .string("John"),
        "extra": .string("not allowed")
      ]),
      against: schema
    )
    #expect(!result.isValid)
    #expect(result.errors[.root]?.contains { error in
      if case .unevaluatedPropertiesFound(let props) = error {
        return props.contains("extra")
      }
      return false
    } == true)
  }
}