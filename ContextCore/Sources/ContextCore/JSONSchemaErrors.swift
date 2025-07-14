// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// Errors that can occur during JSON Schema validation
public enum JSONSchemaValidationError: LocalizedError, Equatable {
  case invalidType(expected: [String], actual: String)
  case valueTooSmall(value: Double, limit: Double, exclusive: Bool)
  case valueTooLarge(value: Double, limit: Double, exclusive: Bool)
  case notMultipleOf(value: Double, divisor: Double)
  case stringTooShort(length: Int, minimum: Int)
  case stringTooLong(length: Int, maximum: Int)
  case patternMismatch(value: String, pattern: String)
  case invalidFormat(value: String, format: String)
  case arrayTooShort(count: Int, minimum: Int)
  case arrayTooLong(count: Int, maximum: Int)
  case duplicateArrayItems
  case containsValidationFailed(minContains: Int?, maxContains: Int?, actualCount: Int)
  case objectTooFewProperties(count: Int, minimum: Int)
  case objectTooManyProperties(count: Int, maximum: Int)
  case missingRequiredProperty(property: String)
  case invalidPropertyName(property: String)
  case dependentPropertyMissing(property: String, dependent: String)
  case constMismatch(expected: JSONValue, actual: JSONValue)
  case enumMismatch(value: JSONValue, options: [JSONValue])
  case notValidationFailed
  case allOfValidationFailed(failures: [Int: [JSONSchemaValidationError]])
  case anyOfValidationFailed
  case oneOfValidationFailed(validCount: Int)
  case conditionalValidationFailed(branch: String)
  case unevaluatedPropertiesFound(properties: [String])
  case unevaluatedItemsFound(indices: [Int])
  case schemaValidationDisabled // For false boolean schema
  case referenceResolutionFailed(reference: String)
  case externalReferenceNotSupported(url: String)
  case invalidSchema(reason: String)
  case unknownKeyword(keyword: String, vocabulary: String?)
  case vocabularyNotSupported(vocabulary: String)
  
  public var errorDescription: String? {
    switch self {
    case .invalidType(let expected, let actual):
      let expectedStr = expected.count == 1 ? expected[0] : expected.joined(separator: " or ")
      return "Expected type \(expectedStr), but got \(actual)"
    case .valueTooSmall(let value, let limit, let exclusive):
      return exclusive ? "Value \(value) must be > \(limit)" : "Value \(value) must be ≥ \(limit)"
    case .valueTooLarge(let value, let limit, let exclusive):
      return exclusive ? "Value \(value) must be < \(limit)" : "Value \(value) must be ≤ \(limit)"
    case .notMultipleOf(let value, let divisor):
      return "Value \(value) must be a multiple of \(divisor)"
    case .stringTooShort(let length, let minimum):
      return "String length \(length) is less than minimum \(minimum)"
    case .stringTooLong(let length, let maximum):
      return "String length \(length) exceeds maximum \(maximum)"
    case .patternMismatch(_, let pattern):
      return "String does not match pattern: \(pattern)"
    case .invalidFormat(_, let format):
      return formatErrorMessage(for: format)
    case .arrayTooShort(let count, let minimum):
      return "Array has \(count) items, minimum \(minimum) required"
    case .arrayTooLong(let count, let maximum):
      return "Array has \(count) items, maximum \(maximum) allowed"
    case .duplicateArrayItems:
      return "Array must contain unique items"
    case .containsValidationFailed(let minContains, let maxContains, let actualCount):
      if let min = minContains, actualCount < min {
        return "Array must contain at least \(min) valid items, but only \(actualCount) found"
      } else if let max = maxContains, actualCount > max {
        return "Array must contain at most \(max) valid items, but \(actualCount) found"
      } else {
        return "Array contains validation failed"
      }
    case .objectTooFewProperties(let count, let minimum):
      return "Object has \(count) properties, minimum \(minimum) required"
    case .objectTooManyProperties(let count, let maximum):
      return "Object has \(count) properties, maximum \(maximum) allowed"
    case .missingRequiredProperty(let property):
      return "Required property '\(property)' is missing"
    case .invalidPropertyName(let property):
      return "Property name '\(property)' is invalid"
    case .dependentPropertyMissing(let property, let dependent):
      return "Property '\(dependent)' is required when '\(property)' is present"
    case .constMismatch:
      return "Value does not match the expected constant"
    case .enumMismatch:
      return "Value is not one of the allowed values"
    case .notValidationFailed:
      return "Value should not validate against the schema"
    case .allOfValidationFailed(let failures):
      let count = failures.count
      return "Failed to validate against \(count) of the allOf schemas"
    case .anyOfValidationFailed:
      return "Failed to validate against any of the anyOf schemas"
    case .oneOfValidationFailed(let validCount):
      if validCount == 0 {
        return "Failed to validate against any of the oneOf schemas"
      } else {
        return "Validated against \(validCount) oneOf schemas, but exactly 1 is required"
      }
    case .conditionalValidationFailed(let branch):
      return "Failed conditional validation at '\(branch)' branch"
    case .unevaluatedPropertiesFound(let properties):
      return "Unevaluated properties found: \(properties.joined(separator: ", "))"
    case .unevaluatedItemsFound(let indices):
      return "Unevaluated items found at indices: \(indices.map(String.init).joined(separator: ", "))"
    case .schemaValidationDisabled:
      return "Schema validation is disabled (false schema)"
    case .referenceResolutionFailed(let reference):
      return "Failed to resolve reference: \(reference)"
    case .externalReferenceNotSupported(let url):
      return "External references are not supported: \(url)"
    case .invalidSchema(let reason):
      return "Invalid schema: \(reason)"
    case .unknownKeyword(let keyword, let vocabulary):
      if let vocabulary = vocabulary {
        return "Unknown keyword '\(keyword)' from vocabulary '\(vocabulary)'"
      } else {
        return "Unknown keyword '\(keyword)'"
      }
    case .vocabularyNotSupported(let vocabulary):
      return "Vocabulary '\(vocabulary)' is not supported"
    }
  }
  
  private func formatErrorMessage(for format: String) -> String {
    switch format {
    case "email":
      return "Invalid email address"
    case "idn-email":
      return "Invalid internationalized email address"
    case "uri", "url":
      return "Invalid URI"
    case "uri-reference":
      return "Invalid URI reference"
    case "iri":
      return "Invalid IRI (Internationalized Resource Identifier)"
    case "iri-reference":
      return "Invalid IRI reference"
    case "uri-template":
      return "Invalid URI template"
    case "date":
      return "Invalid date format (expected: YYYY-MM-DD)"
    case "time":
      return "Invalid time format (expected: HH:MM:SS)"
    case "date-time":
      return "Invalid date-time format (expected: RFC 3339)"
    case "duration":
      return "Invalid duration format (expected: ISO 8601 duration)"
    case "hostname":
      return "Invalid hostname"
    case "idn-hostname":
      return "Invalid internationalized hostname"
    case "ipv4":
      return "Invalid IPv4 address"
    case "ipv6":
      return "Invalid IPv6 address"
    case "uuid":
      return "Invalid UUID"
    case "regex":
      return "Invalid regular expression"
    case "json-pointer":
      return "Invalid JSON Pointer (expected: /path/to/property)"
    case "relative-json-pointer":
      return "Invalid relative JSON Pointer"
    default:
      return "Invalid \(format) format"
    }
  }
}

/// Result of JSON Schema validation
public struct JSONSchemaValidationResult: Sendable {
  public let isValid: Bool
  public let errors: [JSONSchemaValidationPath: [JSONSchemaValidationError]]
  public let annotations: [JSONSchemaValidationPath: [String: JSONValue]]
  
  public init(
    isValid: Bool = true, 
    errors: [JSONSchemaValidationPath: [JSONSchemaValidationError]] = [:],
    annotations: [JSONSchemaValidationPath: [String: JSONValue]] = [:]
  ) {
    self.isValid = isValid
    self.errors = errors
    self.annotations = annotations
  }
  
  /// Merge another validation result into this one
  public func merging(_ other: JSONSchemaValidationResult) -> JSONSchemaValidationResult {
    var mergedErrors = errors
    for (path, errs) in other.errors {
      mergedErrors[path, default: []].append(contentsOf: errs)
    }
    
    var mergedAnnotations = annotations
    for (path, anns) in other.annotations {
      mergedAnnotations[path, default: [:]] = mergedAnnotations[path, default: [:]].merging(anns) { _, new in new }
    }
    
    return JSONSchemaValidationResult(
      isValid: isValid && other.isValid,
      errors: mergedErrors,
      annotations: mergedAnnotations
    )
  }
}

/// Represents a path to a location in a JSON document
public struct JSONSchemaValidationPath: Hashable, CustomStringConvertible, Sendable {
  public let components: [Component]
  
  public enum Component: Hashable, Sendable {
    case root
    case property(String)
    case index(Int)
  }
  
  public static let root = JSONSchemaValidationPath(components: [.root])
  
  public init(components: [Component] = [.root]) {
    self.components = components
  }
  
  public func appending(property: String) -> JSONSchemaValidationPath {
    JSONSchemaValidationPath(components: components + [.property(property)])
  }
  
  public func appending(index: Int) -> JSONSchemaValidationPath {
    JSONSchemaValidationPath(components: components + [.index(index)])
  }
  
  public var description: String {
    components.map { component in
      switch component {
      case .root:
        return "$"
      case .property(let name):
        return ".\(name)"
      case .index(let idx):
        return "[\(idx)]"
      }
    }.joined()
  }
}