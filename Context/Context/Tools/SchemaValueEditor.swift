// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import ContextCore
import Dependencies
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SchemaValueEditor: View {
  let node: SchemaNode
  let schemaValidator: SchemaValidator
  let onToggleExpansion: (String) -> Void
  var onRemoveArrayItem: (() -> Void)? = nil
  var focusedField: FocusState<String?>.Binding
  var onNewPropertyAdded: ((String) -> Void)? = nil
  var onDynamicTypeChange: ((String) -> Void)? = nil
  var selectedDynamicType: String? = nil  // For dynamic properties and array items

  @Binding var value: JSONValue
  @Binding var expandedNodes: Set<String>
  @Binding var validationErrors: [String: String]

  @Environment(\.toolSubmitAction) var toolSubmitAction

  private var isReadOnly: Bool {
    if case .object(let obj) = node.schema,
      case .boolean(true) = obj["readOnly"]
    {
      return true
    }
    return false
  }

  private var isDeprecated: Bool {
    if case .object(let obj) = node.schema,
      case .boolean(true) = obj["deprecated"]
    {
      return true
    }
    return false
  }

  private var nullableTypes: [String]? {
    let types = SchemaValueHelpers.extractTypes(from: node.schema)
    if let types = types, types.contains("null") && types.count > 1 {
      return types
    }
    return nil
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      // Type selector for dynamic properties and array items without schema
      if node.isDynamic || (node.isArrayItem && onDynamicTypeChange != nil) {
        TypeSelector(
          selectedType: Binding(
            get: {
              // For dynamic properties and array items, use the stored type
              if let dynamicType = selectedDynamicType {
                return dynamicType
              }
              return SchemaValueHelpers.extractType(from: node.schema) ?? "string"
            },
            set: { newType in
              // Update the value to match the new type
              // For dynamic properties and array items, always use non-null defaults
              value = SchemaValueHelpers.defaultValueForType(newType, isRequired: true)
              // Notify parent to update the schema
              onDynamicTypeChange?(newType)
              // Don't validate immediately - wait for the parent to update the schema
              // The validation will happen when the view rebuilds with the new schema
            }
          )
        )
      }

      // Main content area
      HStack(spacing: 8) {
        if let types = nullableTypes {
          // Nullable field - show checkbox and editor
          Toggle(
            "",
            isOn: Binding(
              get: { !value.isNull },
              set: { enabled in
                if enabled {
                  // Set to default value for the non-null type
                  if let primaryType = types.first(where: { $0 != "null" }) {
                    value = SchemaValueHelpers.defaultValueForType(
                      primaryType, isRequired: node.isRequired)
                  }
                } else {
                  value = .null
                }
                validateValue()
              }
            )
          )
          .toggleStyle(.checkbox)
          .help(value.isNull ? "Enable this field" : "Disable this field")
          .disabled(isReadOnly)

          if !value.isNull {
            typeBasedEditor
          } else {
            Text("null")
              .font(.system(size: 12, design: .monospaced))
              .foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          typeBasedEditor
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // Validation error display area - fixed width
      HStack(spacing: 4) {
        if let error = validationErrors[node.id] {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundColor(.red)
            .font(.system(size: 12))

          Text(error)
            .font(.caption)
            .foregroundColor(.red)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(error)  // Full error in tooltip
        }
      }
      .frame(width: 250, alignment: .leading)
    }
    .onAppear {
      // Only validate if the field is required or has a non-null value
      if node.isRequired || !value.isNull {
        validateValue()
      }
    }
  }

  @ViewBuilder
  private var typeBasedEditor: some View {
    Group {
      // Handle boolean schema
      if case .boolean(let bool) = node.schema {
        if bool {
          // Schema is true - allow any value, show generic editor
          TextField(
            "Enter value",
            text: Binding(
              get: { 
                // Special handling for null values to show empty string instead of "null"
                if value.isNull {
                  return ""
                }
                return JSONValueUtilities.jsonValueToString(value)
              },
              set: { newValue in
                value = JSONValueUtilities.parseValue(newValue)
                validateValue()
              }
            )
          )
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 12, design: .monospaced))
          .disabled(isReadOnly)
        } else {
          // Schema is false - no value allowed
          Text("No value allowed")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
      } else if let schemaType =
        (selectedDynamicType
          ?? SchemaValueHelpers.extractType(from: node.schema, currentValue: value))
      {
        switch schemaType {
        case "string":
          StringValueEditor(
            node: node,
            value: $value,
            focusedField: focusedField,
            isReadOnly: isReadOnly,
            onValidate: validateValue
          )
        case "number":
          NumberValueEditor(
            node: node,
            value: $value,
            focusedField: focusedField,
            isReadOnly: isReadOnly,
            onValidate: validateValue
          )
        case "integer":
          IntegerValueEditor(
            node: node,
            value: $value,
            focusedField: focusedField,
            isReadOnly: isReadOnly,
            onValidate: validateValue
          )
        case "boolean":
          BooleanValueEditor(
            node: node,
            value: $value,
            focusedField: focusedField,
            isReadOnly: isReadOnly,
            onValidate: validateValue
          )
        case "array":
          ArrayValueEditor(
            node: node,
            value: $value,
            expandedNodes: $expandedNodes,
            isReadOnly: isReadOnly,
            onValidate: validateValue,
            onToggleExpansion: onToggleExpansion
          )
        case "object":
          ObjectValueEditor(
            node: node,
            value: $value,
            expandedNodes: $expandedNodes,
            isReadOnly: isReadOnly,
            onValidate: validateValue,
            onToggleExpansion: onToggleExpansion,
            onNewPropertyAdded: onNewPropertyAdded
          )
        case "null":
          NullValueEditor(value: $value)
        case "never":
          // Special case for false boolean schema
          Text("No value allowed")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        default:
          // Fallback to string editor
          StringValueEditor(
            node: node,
            value: $value,
            focusedField: focusedField,
            isReadOnly: isReadOnly,
            onValidate: validateValue
          )
        }
      } else {
        // If no type specified, default to string editor for dynamic properties
        if node.isDynamic {
          StringValueEditor(
            node: node,
            value: $value,
            focusedField: focusedField,
            isReadOnly: isReadOnly,
            onValidate: validateValue
          )
        } else {
          // Use generic editor for non-dynamic properties without type
          TextField(
            "Enter value",
            text: Binding(
              get: { 
                // Special handling for null values to show empty string instead of "null"
                if value.isNull {
                  return ""
                }
                return JSONValueUtilities.jsonValueToString(value)
              },
              set: { newValue in
                value = JSONValueUtilities.parseValue(newValue)
                validateValue()
              }
            )
          )
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 12, design: .monospaced))
          .disabled(isReadOnly)
        }
      }
    }
  }

  // MARK: - Validation

  private func validateValue() {
    // Skip validation for null values on non-required fields
    if case .null = value, !node.isRequired {
      validationErrors.removeValue(forKey: node.id)
      return
    }

    Task {
      do {
        let result = try await schemaValidator.validate(
          value: value,
          against: node.schema
        )

        await MainActor.run {
          // For arrays and objects, we want to show errors on child items/properties, not on the parent
          let schemaType = SchemaValueHelpers.extractType(from: node.schema)
          if schemaType == "array" {
            // Only show array-level errors (not item validation errors) on the array itself
            handleArrayValidationResult(result)
          } else if schemaType == "object" {
            // Only show object-level errors (not property validation errors) on the object itself
            handleObjectValidationResult(result)
          } else {
            // For non-arrays/objects, show the first error on this node
            if result.isValid {
              validationErrors.removeValue(forKey: node.id)
            } else if let firstError = result.allErrors.first {
              validationErrors[node.id] = firstError.displayMessage
            }
          }
        }
      } catch {
        await MainActor.run {
          validationErrors[node.id] = "Validation error: \(error.localizedDescription)"
        }
      }
    }
  }

  private func handleArrayValidationResult(_ result: ValidationResult) {
    // First, clear any existing error on the array itself
    validationErrors.removeValue(forKey: node.id)

    // Look for array-level errors only (not item errors)
    for (path, validationErrors) in result.errors {
      // Check if this is an error on the array itself (not on array items)
      let isArrayLevelError = path.components.allSatisfy { component in
        if case .index = component {
          return false
        }
        return true
      }

      if isArrayLevelError, let firstValidationError = validationErrors.first {
        // Check if any of the errors in this ValidationError are array-specific
        for error in firstValidationError.errors {
          switch error {
          case .arrayTooShort, .arrayTooLong, .duplicateArrayItems, .containsValidationFailed:
            self.validationErrors[node.id] = error.errorDescription ?? "Array validation failed"
            return
          default:
            // Skip other errors - they should be shown on the items
            break
          }
        }
      }
    }
  }

  private func handleObjectValidationResult(_ result: ValidationResult) {
    // First, clear any existing error on the object itself
    validationErrors.removeValue(forKey: node.id)

    // Look for object-level errors only (not property errors)
    for (path, validationErrors) in result.errors {
      // Check if this is an error on the object itself (not on object properties)
      let isObjectLevelError = path.components.allSatisfy { component in
        if case .property = component {
          return false
        }
        return true
      }

      if isObjectLevelError, let firstValidationError = validationErrors.first {
        // Check if any of the errors in this ValidationError are object-specific
        for error in firstValidationError.errors {
          switch error {
          case .objectTooFewProperties, .objectTooManyProperties,
            .missingRequiredProperty, .invalidPropertyName,
            .dependentPropertyMissing, .unevaluatedPropertiesFound:
            self.validationErrors[node.id] = error.errorDescription ?? "Object validation failed"
            return
          default:
            // Skip other errors - they should be shown on the properties
            break
          }
        }
      }
    }
  }
}
