// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// Main JSON Schema validator that coordinates all validation components
public final class JSONSchemaValidator {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaValidator")
  
  private let referenceResolver: JSONSchemaReferenceResolver
  private let typeValidator = JSONSchemaTypeValidator()
  private let keywordValidator = JSONSchemaKeywordValidator()
  private let compositionValidator = JSONSchemaCompositionValidator()
  private let conditionalValidator = JSONSchemaConditionalValidator()
  
  /// Initialize with optional custom reference resolver
  public init(referenceResolver: JSONSchemaReferenceResolver? = nil) {
    self.referenceResolver = referenceResolver ?? JSONSchemaReferenceResolver()
  }
  
  /// Set the root schema for reference resolution
  public func setRootSchema(_ schema: JSONValue) {
    referenceResolver.setRootSchema(schema)
  }
  
  /// Validate a JSON value against a schema
  public func validate(
    _ value: JSONValue,
    against schema: JSONValue,
    context: JSONSchemaValidationContext? = nil,
    options: JSONSchemaValidationOptions? = nil
  ) async throws -> JSONSchemaValidationResult {
    let validationOptions = options ?? JSONSchemaValidationOptions()
    var validationContext = context ?? JSONSchemaValidationContext(options: validationOptions)
    
    // Set content validator if not provided
    if validationOptions.contentValidator == nil {
      // Set self as content validator to handle contentSchema
      var mutableOptions = validationOptions
      mutableOptions.contentValidator = { [weak self] value, schema, context in
        guard let self = self else {
          return JSONSchemaValidationResult(isValid: false, errors: [:])
        }
        return try await self.validateResolved(value, against: schema, context: context)
      }
      // If we have an existing context, we need to create a new one with the updated options
      if context != nil {
        validationContext = validationContext.createChildContext()
      } else {
        validationContext = JSONSchemaValidationContext(options: mutableOptions)
      }
    }
    
    // Resolve references in the schema first
    let resolvedSchema = try referenceResolver.resolveSchema(schema, in: validationContext)
    
    // Push schema to context stack
    validationContext.pushSchema(SchemaLocation(schema: resolvedSchema))
    defer { validationContext.popSchema() }
    
    let result = try await validateResolved(value, against: resolvedSchema, context: validationContext)
    
    // Add collected annotations to result
    let annotations = validationContext.getCollectedAnnotations()
    return JSONSchemaValidationResult(
      isValid: result.isValid,
      errors: result.errors,
      annotations: annotations
    )
  }
  
  // MARK: - Core Validation
  
  private func validateResolved(
    _ value: JSONValue,
    against schema: JSONValue,
    context: JSONSchemaValidationContext
  ) async throws -> JSONSchemaValidationResult {
    // Handle boolean schemas
    if case .boolean(let bool) = schema {
      if bool {
        // true schema allows any value
        return JSONSchemaValidationResult()
      } else {
        // false schema allows no value
        return JSONSchemaValidationResult(
          isValid: false,
          errors: [context.currentPath: [.schemaValidationDisabled]]
        )
      }
    }
    
    guard case .object(let schemaObj) = schema else {
      // Not a valid schema object
      return JSONSchemaValidationResult(
        isValid: false,
        errors: [context.currentPath: [.invalidSchema(reason: "Schema must be a boolean or object")]]
      )
    }
    
    // Extract metadata
    let metadata = keywordValidator.extractMetadata(from: schemaObj)
    if let dialect = metadata.schema {
      context.dialect = dialect
    }
    if let vocabulary = metadata.vocabulary {
      context.vocabularies = Set(vocabulary.keys.filter { vocabulary[$0] == true })
    }
    
    // Collect annotations
    if context.options.collectAnnotations {
      for (key, value) in schemaObj {
        switch key {
        case "title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly", "$comment":
          context.collectAnnotation(keyword: key, value: value)
        default:
          break
        }
      }
    }
    
    // Check vocabulary constraints if enabled
    if context.options.enforceVocabularies && !context.vocabularies.isEmpty {
      for keyword in schemaObj.keys {
        // Skip meta-schema keywords
        if keyword.hasPrefix("$") && keyword != "$ref" && keyword != "$defs" {
          continue
        }
        
        // Check if keyword belongs to a vocabulary
        let vocabulary = getVocabularyForKeyword(keyword, dialect: context.dialect)
        if let vocabulary = vocabulary, !context.vocabularies.contains(vocabulary) {
          return JSONSchemaValidationResult(
            isValid: false,
            errors: [context.currentPath: [.unknownKeyword(keyword: keyword, vocabulary: vocabulary)]]
          )
        }
      }
    }
    
    var result = JSONSchemaValidationResult()
    
    // Type validation
    if let typeValue = schemaObj["type"] {
      let types: [String]
      if case .string(let type) = typeValue {
        types = [type]
      } else if case .array(let typeArray) = typeValue {
        types = typeArray.compactMap { value in
          if case .string(let type) = value { return type }
          return nil
        }
      } else {
        types = []
      }
      
      if !types.isEmpty && !typeValidator.validateType(value, types: types) {
        let actualType = typeValidator.getType(of: value)
        return JSONSchemaValidationResult(
          isValid: false,
          errors: [context.currentPath: [.invalidType(expected: types, actual: actualType)]]
        )
      }
    }
    
    // Const validation
    if let constValue = schemaObj["const"] {
      result = result.merging(keywordValidator.validateConst(value, const: constValue))
      if !result.isValid { return result }
    }
    
    // Enum validation
    if case .array(let enumValues) = schemaObj["enum"] {
      result = result.merging(keywordValidator.validateEnum(value, enumValues: enumValues))
      if !result.isValid { return result }
    }
    
    // Type-specific validation
    result = result.merging(try await validateByType(value, schema: schemaObj, context: context))
    if !result.isValid { return result }
    
    // Composition validation
    result = result.merging(try await validateComposition(value, schema: schemaObj, context: context))
    if !result.isValid { return result }
    
    // Conditional validation
    result = result.merging(try await conditionalValidator.validateConditional(
      value, schema: schemaObj, context: context, validator: validateResolved
    ))
    if !result.isValid { return result }
    
    // Validate dependent schemas (for objects)
    if case .object(let obj) = value,
       case .object(let depSchemas) = schemaObj["dependentSchemas"] {
      result = result.merging(try await conditionalValidator.validateDependentSchemas(
        obj, dependentSchemas: depSchemas, context: context, validator: validateResolved
      ))
      if !result.isValid { return result }
    }
    
    // Unevaluated properties/items (must be done last)
    result = result.merging(try await validateUnevaluated(value, schema: schemaObj, context: context))
    
    return result
  }
  
  // MARK: - Type-Specific Validation
  
  private func validateByType(
    _ value: JSONValue,
    schema: [String: JSONValue],
    context: JSONSchemaValidationContext
  ) async throws -> JSONSchemaValidationResult {
    switch value {
    case .number(let num):
      return typeValidator.validateNumber(num, schema: schema)
      
    case .integer(let int):
      return typeValidator.validateInteger(int, schema: schema)
      
    case .string(let str):
      var result = await typeValidator.validateString(str, schema: schema, context: context)
      
      // Handle contentSchema validation
      if let contentSchema = schema["contentSchema"], let contentValidator = context.options.contentValidator {
        if let jsonData = str.data(using: .utf8),
           let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData) {
          let contentResult = try await contentValidator(jsonValue, contentSchema, context)
          if !contentResult.isValid {
            result = result.merging(JSONSchemaValidationResult(
              isValid: false,
              errors: [context.currentPath: [.invalidSchema(reason: "Content validation failed")]]
            ))
          }
        }
      }
      
      return result
      
    case .array(let arr):
      var result = typeValidator.validateArray(arr, schema: schema, context: context)
      
      // Validate array items
      result = result.merging(try await validateArrayItems(arr, schema: schema, context: context))
      
      // Contains validation
      if let containsSchema = schema["contains"] {
        let minContains = schema["minContains"].flatMap { value in
          if case .integer(let min) = value { return Int(min) }
          return nil
        }
        let maxContains = schema["maxContains"].flatMap { value in
          if case .integer(let max) = value { return Int(max) }
          return nil
        }
        
        result = result.merging(try await conditionalValidator.validateContains(
          arr, containsSchema: containsSchema, minContains: minContains, maxContains: maxContains,
          context: context, validator: validateResolved
        ))
      }
      
      return result
      
    case .object(let obj):
      var result = await typeValidator.validateObject(obj, schema: schema, context: context)
      
      // Validate object properties
      result = result.merging(try await validateObjectProperties(obj, schema: schema, context: context))
      
      // Property names validation
      if let propertyNamesSchema = schema["propertyNames"] {
        result = result.merging(try await keywordValidator.validatePropertyNames(
          Set(obj.keys), 
          schema: propertyNamesSchema, 
          validator: { value, schema in
            try await validateResolved(value, against: schema, context: context)
          }
        ))
      }
      
      // Pattern properties validation
      if case .object(let patternProps) = schema["patternProperties"] {
        result = result.merging(try await conditionalValidator.validatePatternProperties(
          obj, patternProperties: patternProps, context: context, validator: validateResolved
        ))
      }
      
      return result
      
    default:
      return JSONSchemaValidationResult()
    }
  }
  
  // MARK: - Array Items Validation
  
  private func validateArrayItems(
    _ array: [JSONValue],
    schema: [String: JSONValue],
    context: JSONSchemaValidationContext
  ) async throws -> JSONSchemaValidationResult {
    var allErrors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:]
    
    let isModernDialect = isModernDialect(context.dialect)
    
    // Handle prefixItems (tuple validation) - 2020-12 and later
    if case .array(let prefixItems) = schema["prefixItems"] {
      var startIndex = 0
      
      for (index, item) in array.enumerated() {
        context.pushPath(index: index)
        defer { context.popPath() }
        
        if index < prefixItems.count {
          // Validate against specific schema for this position
          let itemResult = try await validateResolved(item, against: prefixItems[index], context: context)
          if !itemResult.isValid {
            for (path, errors) in itemResult.errors {
              let fullPath = path == .root ? context.currentPath : path
              allErrors[fullPath, default: []].append(contentsOf: errors)
            }
          } else {
            context.markItemEvaluated(index)
          }
          startIndex = index + 1
        }
      }
      
      // In 2020-12, items applies to elements after prefixItems
      if let itemsSchema = schema["items"], startIndex < array.count {
        for index in startIndex..<array.count {
          context.pushPath(index: index)
          defer { context.popPath() }
          
          let itemResult = try await validateResolved(array[index], against: itemsSchema, context: context)
          if !itemResult.isValid {
            for (path, errors) in itemResult.errors {
              let fullPath = path == .root ? context.currentPath : path
              allErrors[fullPath, default: []].append(contentsOf: errors)
            }
          } else {
            context.markItemEvaluated(index)
          }
        }
      }
      
      // Handle legacy additionalItems for backward compatibility
      if let additionalItemsSchema = schema["additionalItems"], schema["items"] == nil {
        for index in prefixItems.count..<array.count {
          context.pushPath(index: index)
          defer { context.popPath() }
          
          if case .boolean(false) = additionalItemsSchema {
            allErrors[context.currentPath, default: []].append(
              .arrayTooLong(count: array.count, maximum: prefixItems.count)
            )
          } else {
            let itemResult = try await validateResolved(array[index], against: additionalItemsSchema, context: context)
            if !itemResult.isValid {
              for (path, errors) in itemResult.errors {
                let fullPath = path == .root ? context.currentPath : path
                allErrors[fullPath, default: []].append(contentsOf: errors)
              }
            } else {
              context.markItemEvaluated(index)
            }
          }
        }
      }
    } else if let itemsSchema = schema["items"] {
      // Pre-2020-12 behavior or when no prefixItems
      if case .array(let itemSchemas) = itemsSchema, !isModernDialect {
        // Tuple validation (draft-07 and earlier)
        for (index, item) in array.enumerated() {
          context.pushPath(index: index)
          defer { context.popPath() }
          
          if index < itemSchemas.count {
            let itemResult = try await validateResolved(item, against: itemSchemas[index], context: context)
            if !itemResult.isValid {
              for (path, errors) in itemResult.errors {
                let fullPath = path == .root ? context.currentPath : path
                allErrors[fullPath, default: []].append(contentsOf: errors)
              }
            } else {
              context.markItemEvaluated(index)
            }
          } else if let additionalItemsSchema = schema["additionalItems"] {
            if case .boolean(false) = additionalItemsSchema {
              allErrors[context.currentPath, default: []].append(
                .arrayTooLong(count: array.count, maximum: itemSchemas.count)
              )
            } else {
              let itemResult = try await validateResolved(item, against: additionalItemsSchema, context: context)
              if !itemResult.isValid {
                for (path, errors) in itemResult.errors {
                  let fullPath = path == .root ? context.currentPath : path
                  allErrors[fullPath, default: []].append(contentsOf: errors)
                }
              } else {
                context.markItemEvaluated(index)
              }
            }
          }
        }
      } else {
        // Uniform items validation
        for (index, item) in array.enumerated() {
          context.pushPath(index: index)
          defer { context.popPath() }
          
          let itemResult = try await validateResolved(item, against: itemsSchema, context: context)
          if !itemResult.isValid {
            for (path, errors) in itemResult.errors {
              let fullPath = path == .root ? context.currentPath : path
              allErrors[fullPath, default: []].append(contentsOf: errors)
            }
          } else {
            context.markItemEvaluated(index)
          }
        }
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: allErrors.isEmpty,
      errors: allErrors
    )
  }
  
  // MARK: - Object Properties Validation
  
  private func validateObjectProperties(
    _ object: [String: JSONValue],
    schema: [String: JSONValue],
    context: JSONSchemaValidationContext
  ) async throws -> JSONSchemaValidationResult {
    var allErrors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:]
    
    // Get defined properties
    let properties = schema["properties"].flatMap { value -> [String: JSONValue]? in
      if case .object(let props) = value { return props }
      return nil
    } ?? [:]
    
    // Get pattern properties
    let patternProperties = keywordValidator.extractPatternProperties(from: schema) ?? []
    
    // Validate each property
    for (propertyName, propertyValue) in object {
      var validated = false
      
      // Check against defined properties
      if let propertySchema = properties[propertyName] {
        context.pushPath(property: propertyName)
        
        let result = try await validateResolved(propertyValue, against: propertySchema, context: context)
        if !result.isValid {
          for (path, errors) in result.errors {
            let fullPath = path == .root ? context.currentPath : path
            allErrors[fullPath, default: []].append(contentsOf: errors)
          }
        }
        
        context.popPath()
        
        // Mark property as evaluated at the object level (after popping back to object context)
        context.markPropertyEvaluated(propertyName)
        validated = true
      }
      
      // Check against pattern properties (already handled in validateByType)
      
      // Check against additionalProperties if not validated yet
      if !validated && !patternProperties.isEmpty {
        let matches = await keywordValidator.matchPatternProperties(
          propertyName: propertyName,
          patternProperties: patternProperties
        )
        if !matches.isEmpty {
          validated = true
        }
      }
      
      if !validated {
        if let additionalPropsSchema = schema["additionalProperties"] {
          if case .boolean(false) = additionalPropsSchema {
            allErrors[context.currentPath, default: []].append(
              .invalidSchema(reason: "Additional property '\(propertyName)' is not allowed")
            )
          } else {
            context.pushPath(property: propertyName)
            let result = try await validateResolved(propertyValue, against: additionalPropsSchema, context: context)
            if !result.isValid {
              for (path, errors) in result.errors {
                let fullPath = path == .root ? context.currentPath : path
                allErrors[fullPath, default: []].append(contentsOf: errors)
              }
            } else {
              // Mark as evaluated when validation passes
              context.markPropertyEvaluated(propertyName)
            }
            context.popPath()
          }
        } else {
          // additionalProperties defaults to true when not present
          // But we should NOT mark as evaluated - unevaluatedProperties should still catch these
        }
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: allErrors.isEmpty,
      errors: allErrors
    )
  }
  
  // MARK: - Composition Validation
  
  private func validateComposition(
    _ value: JSONValue,
    schema: [String: JSONValue],
    context: JSONSchemaValidationContext
  ) async throws -> JSONSchemaValidationResult {
    var result = JSONSchemaValidationResult()
    
    // allOf
    if case .array(let allOfSchemas) = schema["allOf"] {
      result = result.merging(try await compositionValidator.validateAllOf(
        value, schemas: allOfSchemas, context: context, validator: validateResolved
      ))
      if !result.isValid { return result }
    }
    
    // anyOf
    if case .array(let anyOfSchemas) = schema["anyOf"] {
      result = result.merging(try await compositionValidator.validateAnyOf(
        value, schemas: anyOfSchemas, context: context, validator: validateResolved
      ))
      if !result.isValid { return result }
    }
    
    // oneOf
    if case .array(let oneOfSchemas) = schema["oneOf"] {
      result = result.merging(try await compositionValidator.validateOneOf(
        value, schemas: oneOfSchemas, context: context, validator: validateResolved
      ))
      if !result.isValid { return result }
    }
    
    // not
    if let notSchema = schema["not"] {
      result = result.merging(try await compositionValidator.validateNot(
        value, schema: notSchema, context: context, validator: validateResolved
      ))
    }
    
    return result
  }
  
  // MARK: - Unevaluated Properties/Items
  
  private func validateUnevaluated(
    _ value: JSONValue,
    schema: [String: JSONValue],
    context: JSONSchemaValidationContext
  ) async throws -> JSONSchemaValidationResult {
    var result = JSONSchemaValidationResult()
    
    switch value {
    case .object(let obj):
      if let unevaluatedPropsSchema = schema["unevaluatedProperties"] {
        result = result.merging(try await conditionalValidator.validateUnevaluatedProperties(
          obj, unevaluatedPropertiesSchema: unevaluatedPropsSchema,
          context: context, validator: validateResolved
        ))
      }
      
    case .array(let arr):
      if let unevaluatedItemsSchema = schema["unevaluatedItems"] {
        result = result.merging(try await conditionalValidator.validateUnevaluatedItems(
          arr, unevaluatedItemsSchema: unevaluatedItemsSchema,
          context: context, validator: validateResolved
        ))
      }
      
    default:
      break
    }
    
    return result
  }
  
  // MARK: - Vocabulary and Dialect Support
  
  private func getKnownKeywords(for dialect: String) -> Set<String> {
    // Common keywords across all dialects
    var keywords: Set<String> = [
      // Core
      "$schema", "$id", "$ref", "$anchor", "$dynamicRef", "$dynamicAnchor", "$defs", "$vocabulary", "$comment",
      // Applicators
      "allOf", "anyOf", "oneOf", "not", "if", "then", "else",
      "properties", "patternProperties", "additionalProperties", "propertyNames",
      "prefixItems", "items", "additionalItems", "contains",
      "dependentSchemas",
      // Validators
      "type", "const", "enum",
      "multipleOf", "maximum", "exclusiveMaximum", "minimum", "exclusiveMinimum",
      "maxLength", "minLength", "pattern", "format",
      "maxItems", "minItems", "uniqueItems", "maxContains", "minContains",
      "maxProperties", "minProperties", "required", "dependentRequired",
      // Annotations
      "title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly",
      // Content
      "contentEncoding", "contentMediaType", "contentSchema",
      // Unevaluated
      "unevaluatedProperties", "unevaluatedItems"
    ]
    
    // Add dialect-specific keywords
    if dialect.contains("2019-09") || dialect.contains("2020-12") {
      keywords.formUnion(["$recursiveRef", "$recursiveAnchor"])
    }
    
    if dialect.contains("draft-07") || dialect.contains("draft-06") || dialect.contains("draft-04") {
      keywords.insert("definitions") // older name for $defs
    }
    
    return keywords
  }
  
  private func getVocabularyForKeyword(_ keyword: String, dialect: String?) -> String? {
    switch keyword {
    case "$schema", "$id", "$ref", "$anchor", "$dynamicRef", "$dynamicAnchor", "$defs", "$vocabulary", "$comment":
      return "https://json-schema.org/draft/2020-12/vocab/core"
    case "allOf", "anyOf", "oneOf", "not", "if", "then", "else", "properties", "patternProperties", 
         "additionalProperties", "propertyNames", "prefixItems", "items", "contains", "dependentSchemas":
      return "https://json-schema.org/draft/2020-12/vocab/applicator"
    case "type", "const", "enum", "multipleOf", "maximum", "exclusiveMaximum", "minimum", "exclusiveMinimum",
         "maxLength", "minLength", "pattern", "maxItems", "minItems", "uniqueItems", "maxContains", "minContains",
         "maxProperties", "minProperties", "required", "dependentRequired":
      return "https://json-schema.org/draft/2020-12/vocab/validation"
    case "format":
      return "https://json-schema.org/draft/2020-12/vocab/format-annotation"
    case "title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly":
      return "https://json-schema.org/draft/2020-12/vocab/meta-data"
    case "contentEncoding", "contentMediaType", "contentSchema":
      return "https://json-schema.org/draft/2020-12/vocab/content"
    case "unevaluatedProperties", "unevaluatedItems":
      return "https://json-schema.org/draft/2020-12/vocab/unevaluated"
    default:
      return nil
    }
  }
  
  private func isModernDialect(_ dialect: String?) -> Bool {
    guard let dialect = dialect else { return true } // Default to modern behavior
    return dialect.contains("2019-09") || dialect.contains("2020-12") || !dialect.contains("draft-")
  }
}