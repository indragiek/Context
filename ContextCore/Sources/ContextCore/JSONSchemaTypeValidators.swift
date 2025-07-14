// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// Validates type-specific constraints in JSON Schema
public struct JSONSchemaTypeValidator {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaTypeValidator")
  private let formatValidator = JSONSchemaFormatValidator()
  private let contentValidator = JSONSchemaContentValidator()
  
  public init() {}
  
  // MARK: - Type Validation
  
  /// Check if a value matches the expected type(s)
  public func validateType(_ value: JSONValue, types: [String]) -> Bool {
    for type in types {
      if matchesType(value, type: type) {
        return true
      }
    }
    return false
  }
  
  /// Check if a value matches a specific type
  public func matchesType(_ value: JSONValue, type: String) -> Bool {
    switch (value, type) {
    case (.null, "null"):
      return true
    case (.boolean, "boolean"):
      return true
    case (.string, "string"):
      return true
    case (.number, "number"):
      return true
    case (.integer, "integer"):
      return true
    case (.integer(_), "number"):
      // Integers are also valid numbers
      return true
    case (.number(let n), "integer"):
      // Check if number is actually an integer
      return n.truncatingRemainder(dividingBy: 1) == 0
    case (.array, "array"):
      return true
    case (.object, "object"):
      return true
    default:
      return false
    }
  }
  
  /// Get the JSON type of a value
  public func getType(of value: JSONValue) -> String {
    switch value {
    case .null:
      return "null"
    case .boolean:
      return "boolean"
    case .string:
      return "string"
    case .number:
      return "number"
    case .integer:
      return "integer"
    case .array:
      return "array"
    case .object:
      return "object"
    }
  }
  
  // MARK: - Numeric Validation
  
  public func validateNumber(_ value: Double, schema: [String: JSONValue]) -> JSONSchemaValidationResult {
    var errors: [JSONSchemaValidationError] = []
    
    // minimum
    if case .number(let min) = schema["minimum"] {
      if value < min {
        errors.append(.valueTooSmall(value: value, limit: min, exclusive: false))
      }
    } else if case .integer(let min) = schema["minimum"] {
      if value < Double(min) {
        errors.append(.valueTooSmall(value: value, limit: Double(min), exclusive: false))
      }
    }
    
    // exclusiveMinimum
    if case .number(let exMin) = schema["exclusiveMinimum"] {
      if value <= exMin {
        errors.append(.valueTooSmall(value: value, limit: exMin, exclusive: true))
      }
    } else if case .integer(let exMin) = schema["exclusiveMinimum"] {
      if value <= Double(exMin) {
        errors.append(.valueTooSmall(value: value, limit: Double(exMin), exclusive: true))
      }
    }
    
    // maximum
    if case .number(let max) = schema["maximum"] {
      if value > max {
        errors.append(.valueTooLarge(value: value, limit: max, exclusive: false))
      }
    } else if case .integer(let max) = schema["maximum"] {
      if value > Double(max) {
        errors.append(.valueTooLarge(value: value, limit: Double(max), exclusive: false))
      }
    }
    
    // exclusiveMaximum
    if case .number(let exMax) = schema["exclusiveMaximum"] {
      if value >= exMax {
        errors.append(.valueTooLarge(value: value, limit: exMax, exclusive: true))
      }
    } else if case .integer(let exMax) = schema["exclusiveMaximum"] {
      if value >= Double(exMax) {
        errors.append(.valueTooLarge(value: value, limit: Double(exMax), exclusive: true))
      }
    }
    
    // multipleOf
    if case .number(let multiple) = schema["multipleOf"], multiple > 0 {
      let remainder = value.truncatingRemainder(dividingBy: multiple)
      // Use epsilon for floating point comparison
      let epsilon = 1e-10
      if abs(remainder) > epsilon && abs(remainder - multiple) > epsilon {
        errors.append(.notMultipleOf(value: value, divisor: multiple))
      }
    } else if case .integer(let multiple) = schema["multipleOf"], multiple > 0 {
      let remainder = value.truncatingRemainder(dividingBy: Double(multiple))
      let epsilon = 1e-10
      if abs(remainder) > epsilon && abs(remainder - Double(multiple)) > epsilon {
        errors.append(.notMultipleOf(value: value, divisor: Double(multiple)))
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: errors.isEmpty,
      errors: errors.isEmpty ? [:] : [.root: errors]
    )
  }
  
  public func validateInteger(_ value: Int64, schema: [String: JSONValue]) -> JSONSchemaValidationResult {
    // Convert to Double and use number validation
    return validateNumber(Double(value), schema: schema)
  }
  
  // MARK: - String Validation
  
  public func validateString(
    _ value: String, 
    schema: [String: JSONValue], 
    context: JSONSchemaValidationContext? = nil
  ) async -> JSONSchemaValidationResult {
    var errors: [JSONSchemaValidationError] = []
    
    // minLength
    if case .integer(let minLen) = schema["minLength"] {
      if value.count < Int(minLen) {
        errors.append(.stringTooShort(length: value.count, minimum: Int(minLen)))
      }
    }
    
    // maxLength
    if case .integer(let maxLen) = schema["maxLength"] {
      if value.count > Int(maxLen) {
        errors.append(.stringTooLong(length: value.count, maximum: Int(maxLen)))
      }
    }
    
    // pattern
    if case .string(let pattern) = schema["pattern"] {
      let maxTime = context?.options.maxRegexEvaluationTime ?? 2.0
      let matches = await value.matchesPattern(pattern, timeout: maxTime)
      if !matches {
        errors.append(.patternMismatch(value: value, pattern: pattern))
      }
    }
    
    // format - only validate if enabled
    if case .string(let format) = schema["format"] {
      let shouldValidateFormat = context?.options.validateFormats ?? true
      if shouldValidateFormat {
        let isValid = await formatValidator.validate(value, format: format)
        if !isValid {
          errors.append(.invalidFormat(value: value, format: format))
        }
      } else if context?.options.collectAnnotations == true {
        // Collect format as annotation when not validating
        context?.collectAnnotation(keyword: "format", value: .string(format))
      }
    }
    
    // contentSchema - validate string content as JSON against a schema
    // Note: contentSchema validation is handled in JSONSchemaValidator
    if schema["contentSchema"] != nil {
      // Only check if it's valid JSON for contentMediaType validation
      if let jsonData = value.data(using: .utf8) {
        do {
          _ = try JSONDecoder().decode(JSONValue.self, from: jsonData)
          // Valid JSON - contentSchema will be validated in JSONSchemaValidator
        } catch {
          // Not valid JSON - contentSchema validation will be skipped
          // But contentMediaType validation should still happen if present
        }
      }
    }
    
    // contentMediaType and contentEncoding (only validate if format validation is enabled)
    // Note: When contentSchema is present, contentMediaType validation is usually skipped
    // as contentSchema provides stronger validation
    if let mediaType = schema["contentMediaType"],
       case .string(let mediaTypeStr) = mediaType,
       schema["contentSchema"] == nil {  // Only validate contentMediaType when contentSchema is not present
      let shouldValidateContent = context?.options.validateFormats ?? true
      if shouldValidateContent {
        if let encoding = schema["contentEncoding"],
           case .string(let encodingStr) = encoding {
          if !contentValidator.validateEncodedContent(value, mediaType: mediaTypeStr, encoding: encodingStr) {
            errors.append(.invalidSchema(reason: "Invalid \(encodingStr) encoded \(mediaTypeStr) content"))
          }
        } else {
          // No encoding specified, validate raw content
          if !contentValidator.validateMediaType(value, mediaType: mediaTypeStr) {
            errors.append(.invalidSchema(reason: "Invalid \(mediaTypeStr) content"))
          }
        }
      } else if context?.options.collectAnnotations == true {
        // Collect as annotations when not validating
        context?.collectAnnotation(keyword: "contentMediaType", value: .string(mediaTypeStr))
        if let encoding = schema["contentEncoding"], case .string(let enc) = encoding {
          context?.collectAnnotation(keyword: "contentEncoding", value: .string(enc))
        }
      }
    }
    
    return JSONSchemaValidationResult(
      isValid: errors.isEmpty,
      errors: errors.isEmpty ? [:] : [.root: errors]
    )
  }
  
  // MARK: - Array Validation
  
  public func validateArray(
    _ value: [JSONValue],
    schema: [String: JSONValue],
    context: JSONSchemaValidationContext
  ) -> JSONSchemaValidationResult {
    var errors: [JSONSchemaValidationError] = []
    
    // minItems
    if case .integer(let minItems) = schema["minItems"] {
      if value.count < Int(minItems) {
        errors.append(.arrayTooShort(count: value.count, minimum: Int(minItems)))
      }
    }
    
    // maxItems
    if case .integer(let maxItems) = schema["maxItems"] {
      if value.count > Int(maxItems) {
        errors.append(.arrayTooLong(count: value.count, maximum: Int(maxItems)))
      }
    }
    
    // uniqueItems
    if case .boolean(true) = schema["uniqueItems"] {
      if !hasUniqueItems(value) {
        errors.append(.duplicateArrayItems)
      }
    }
    
    // contains, minContains, maxContains validation would be handled by the main validator
    // as it requires validating against subschemas
    
    return JSONSchemaValidationResult(
      isValid: errors.isEmpty,
      errors: errors.isEmpty ? [:] : [.root: errors]
    )
  }
  
  private func hasUniqueItems(_ array: [JSONValue]) -> Bool {
    // Use Set to check for uniqueness
    var seen = Set<String>()
    for item in array {
      let key = canonicalJSONString(for: item)
      if seen.contains(key) {
        return false
      }
      seen.insert(key)
    }
    return true
  }
  
  private func canonicalJSONString(for value: JSONValue) -> String {
    // Create a canonical string representation for comparison
    switch value {
    case .null:
      return "null"
    case .boolean(let b):
      return b ? "true" : "false"
    case .integer(let i):
      return String(i)
    case .number(let n):
      return String(n)
    case .string(let s):
      return "\"\(s)\""
    case .array(let arr):
      let items = arr.map { canonicalJSONString(for: $0) }.joined(separator: ",")
      return "[\(items)]"
    case .object(let obj):
      let pairs = obj.keys.sorted().map { key in
        "\"\(key)\":\(canonicalJSONString(for: obj[key]!))"
      }.joined(separator: ",")
      return "{\(pairs)}"
    }
  }
  
  // MARK: - Object Validation
  
  public func validateObject(
    _ value: [String: JSONValue],
    schema: [String: JSONValue],
    context: JSONSchemaValidationContext
  ) async -> JSONSchemaValidationResult {
    var errors: [JSONSchemaValidationError] = []
    var pathErrors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:]
    
    // minProperties
    if case .integer(let minProps) = schema["minProperties"] {
      if value.count < Int(minProps) {
        errors.append(.objectTooFewProperties(count: value.count, minimum: Int(minProps)))
      }
    }
    
    // maxProperties
    if case .integer(let maxProps) = schema["maxProperties"] {
      if value.count > Int(maxProps) {
        errors.append(.objectTooManyProperties(count: value.count, maximum: Int(maxProps)))
      }
    }
    
    // required
    if case .array(let requiredArray) = schema["required"] {
      for required in requiredArray {
        if case .string(let propName) = required {
          if value[propName] == nil {
            errors.append(.missingRequiredProperty(property: propName))
          }
        }
      }
    }
    
    // propertyNames - validate that all property names match the schema
    if schema["propertyNames"] != nil {
      for key in value.keys {
        // This would need string validation from the main validator
        logger.debug("propertyNames validation deferred to main validator for key: \(key)")
      }
    }
    
    // dependentRequired
    if case .object(let depRequired) = schema["dependentRequired"] {
      for (key, deps) in depRequired {
        if value[key] != nil {
          // Property exists, check dependencies
          if case .array(let depArray) = deps {
            for dep in depArray {
              if case .string(let depKey) = dep {
                if value[depKey] == nil {
                  errors.append(.dependentPropertyMissing(property: key, dependent: depKey))
                }
              }
            }
          }
        }
      }
    }
    
    if !errors.isEmpty {
      pathErrors[.root] = errors
    }
    
    return JSONSchemaValidationResult(
      isValid: errors.isEmpty && pathErrors.isEmpty,
      errors: pathErrors
    )
  }
}