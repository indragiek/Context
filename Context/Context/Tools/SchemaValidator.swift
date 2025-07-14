// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation

/// Provides JSON Schema validation using ContextCore validators
@MainActor
final class SchemaValidator {
  nonisolated(unsafe) private let validator = JSONSchemaValidator()
  private let resolver = JSONSchemaReferenceResolver()

  /// Validates a value against a schema
  func validate(
    value: JSONValue,
    against schema: JSONValue
  ) async throws -> ValidationResult {
    let result = try await validator.validate(value, against: schema)
    return ValidationResult(from: result)
  }
  
  /// Resolves a schema that may contain references
  func resolveSchema(_ schema: JSONValue) -> JSONValue {
    let context = JSONSchemaValidationContext()
    do {
      return try resolver.resolveSchema(schema, in: context)
    } catch {
      // If resolution fails, return the original schema
      return schema
    }
  }
  
  /// Sets the root schema for reference resolution
  func setRootSchema(_ schema: JSONValue?) {
    resolver.setRootSchema(schema)
  }
}

/// Represents a validation error with structured information
struct ValidationError: Equatable {
  let path: JSONSchemaValidationPath
  let errors: [JSONSchemaValidationError]
  
  init(path: JSONSchemaValidationPath, errors: [JSONSchemaValidationError]) {
    self.path = path
    self.errors = errors
  }
  
  init(from result: JSONSchemaValidationResult) {
    // Take the first error path and its errors
    if let firstError = result.errors.first {
      self.path = firstError.key
      self.errors = firstError.value
    } else {
      self.path = .root
      self.errors = []
    }
  }
  
  /// Primary error message for display
  var displayMessage: String {
    errors.first?.errorDescription ?? "Validation failed"
  }
  
  /// Detailed error description with all errors
  var detailedDescription: String {
    errors.compactMap(\.errorDescription).joined(separator: "\n")
  }
  
  /// Whether this is a critical error that should block form submission
  var isCritical: Bool {
    errors.contains { error in
      switch error {
      case .missingRequiredProperty, .invalidType, .schemaValidationDisabled:
        return true
      default:
        return false
      }
    }
  }
}

/// Complete validation result for an entire form
struct ValidationResult: Sendable {
  let isValid: Bool
  let errors: [JSONSchemaValidationPath: [ValidationError]]
  
  init(isValid: Bool, errors: [JSONSchemaValidationPath: [ValidationError]] = [:]) {
    self.isValid = isValid
    self.errors = errors
  }
  
  init(from result: JSONSchemaValidationResult) {
    self.isValid = result.isValid
    self.errors = result.errors.mapValues { schemaErrors in
      schemaErrors.map { error in
        ValidationError(path: .root, errors: [error])
      }
    }
  }
  
  /// All validation errors flattened
  var allErrors: [ValidationError] {
    errors.values.flatMap { $0 }
  }
  
  /// Critical errors that should block form submission
  var criticalErrors: [ValidationError] {
    allErrors.filter(\.isCritical)
  }
  
  /// Whether there are any critical errors
  var hasCriticalErrors: Bool {
    !criticalErrors.isEmpty
  }
}

