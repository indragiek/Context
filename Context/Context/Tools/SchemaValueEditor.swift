// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct SchemaValueEditor: View {
  let node: SchemaNode
  @Binding var value: JSONValue
  @Binding var expandedNodes: Set<String>
  let onToggleExpansion: (String) -> Void
  var onRemoveArrayItem: (() -> Void)? = nil
  var focusedField: FocusState<String?>.Binding
  var onTabPressed: (() -> Void)?
  @Environment(\.toolSubmitAction) var toolSubmitAction

  var body: some View {
    if let schemaType = extractType(from: node.schema) {
      switch schemaType {
      case "string":
        stringEditor
      case "number":
        numberEditor
      case "integer":
        integerEditor
      case "boolean":
        booleanEditor
      case "array":
        arrayEditor
      case "object":
        objectEditor
      case "null":
        nullEditor
      default:
        // Fallback to string editor
        stringEditor
      }
    } else {
      // If no type specified, use generic editor
      TextField(
        "Enter value",
        text: Binding(
          get: { valueToString(value) },
          set: { newValue in
            value = parseValue(newValue)
          }
        )
      )
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 12, design: .monospaced))
    }
  }

  private var stringEditor: some View {
    HStack {
      if let enumValues = extractEnum(from: node.schema) {
        let stringEnums = enumValues.compactMap { enumStringValue($0) }
        if !stringEnums.isEmpty {
          // Use Picker for enum values
          Picker(
            "",
            selection: Binding(
              get: {
                if case .string(let str) = value, stringEnums.contains(str) {
                  return str
                }
                // Return first enum value as fallback for display only
                return stringEnums.first ?? ""
              },
              set: { newValue in
                value = .string(newValue)
              }
            )
          ) {
            ForEach(stringEnums, id: \.self) { option in
              Text(option).tag(option)
            }
          }
          .labelsHidden()
          .onAppear {
            // Always ensure we have a valid enum value selected
            if case .string(let str) = value, stringEnums.contains(str) {
              // Current value is valid, keep it
              return
            }
            // Current value is invalid, missing, or not a string - set to first enum option
            if let firstEnum = stringEnums.first {
              value = .string(firstEnum)
            }
          }
        } else {
          // Fallback to text field if enum values are empty
          textFieldEditor
        }
      } else {
        textFieldEditor
      }
    }
  }

  private var textFieldEditor: some View {
    TextField(
      "Enter text",
      text: Binding(
        get: {
          if case .string(let str) = value {
            return str
          }
          return ""
        },
        set: { newValue in
          value = .string(newValue)
        }
      )
    )
    .textFieldStyle(.roundedBorder)
    .font(.system(size: 12, design: .monospaced))
    .focused(focusedField, equals: node.id)
    .onSubmit {
      toolSubmitAction?()
    }
    .onKeyPress(.tab) {
      onTabPressed?()
      return .handled
    }
    .submitLabel(.done)
  }

  private var numberEditor: some View {
    HStack {
      Stepper(
        value: Binding(
          get: {
            if case .number(let num) = value {
              return num
            }
            return 0.0
          },
          set: { newValue in
            value = .number(newValue)
          }
        ),
        step: extractStep(from: node.schema)
      ) {
        TextField(
          "0.0",
          value: Binding(
            get: {
              if case .number(let num) = value {
                return num
              }
              return 0.0
            },
            set: { newValue in
              value = .number(newValue)
            }
          ),
          format: .number
        )
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, design: .monospaced))
        .frame(width: 100)
        .focused(focusedField, equals: node.id)
        .onSubmit {
          toolSubmitAction?()
        }
        .onKeyPress(.tab) {
          onTabPressed?()
          return .handled
        }
        .submitLabel(.done)
      }
    }
  }

  private var integerEditor: some View {
    HStack {
      Stepper(
        value: Binding(
          get: {
            if case .integer(let int) = value {
              return Int(int)
            }
            return 0
          },
          set: { newValue in
            value = .integer(Int64(newValue))
          }
        ),
        step: 1
      ) {
        TextField(
          "0",
          value: Binding(
            get: {
              if case .integer(let int) = value {
                return Int(int)
              }
              return 0
            },
            set: { newValue in
              value = .integer(Int64(newValue))
            }
          ),
          format: .number
        )
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, design: .monospaced))
        .frame(width: 100)
        .focused(focusedField, equals: node.id)
        .onSubmit {
          toolSubmitAction?()
        }
        .onKeyPress(.tab) {
          onTabPressed?()
          return .handled
        }
        .submitLabel(.done)
      }
    }
  }

  private var booleanEditor: some View {
    HStack {
      Toggle(
        "",
        isOn: Binding(
          get: {
            if case .boolean(let bool) = value {
              return bool
            }
            return false
          },
          set: { newValue in
            value = .boolean(newValue)
          }
        )
      )
      .toggleStyle(.switch)
      .controlSize(.small)
      .labelsHidden()

      Spacer()
    }
  }

  private var arrayEditor: some View {
    HStack {
      if case .array(let items) = value {
        Text("\(items.count) items")
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
      } else {
        Text("Empty array")
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
      }

      Spacer()

      // Remove item button (for array items)
      if node.isArrayItem {
        Button(action: {
          // Remove this array item
          removeArrayItem()
        }) {
          Image(systemName: "minus.circle")
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
        .help("Remove this item")
      }

      Button(action: {
        // Add new item
        if case .array(var items) = value {
          items.append(defaultValueForSchema(extractItems(from: node.schema) ?? .object([:])))
          value = .array(items)
        } else {
          value = .array([defaultValueForSchema(extractItems(from: node.schema) ?? .object([:]))])
        }
        // Auto-expand this node to show the new item
        onToggleExpansion(node.id)
      }) {
        Image(systemName: "plus.circle")
          .foregroundColor(.accentColor)
      }
      .buttonStyle(.plain)
      .help("Add new item")
    }
  }

  private var objectEditor: some View {
    HStack {
      // Count the properties from the schema, not from the value
      let childCount = countObjectChildren()
      if childCount > 0 {
        Text("\(childCount) \(childCount == 1 ? "property" : "properties")")
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
      } else {
        Text("Empty object")
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
      }

      Spacer()
    }
  }

  private func countObjectChildren() -> Int {
    if let properties = extractProperties(from: node.schema) {
      return properties.count
    }
    return 0
  }

  private var nullEditor: some View {
    Text("null")
      .font(.system(size: 12, design: .monospaced))
      .foregroundColor(.secondary)
      .onAppear {
        value = .null
      }
  }

  private func extractType(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let typeStr) = obj["type"]
    {
      return typeStr
    }
    return nil
  }

  private func extractEnum(from schema: JSONValue) -> [JSONValue]? {
    if case .object(let obj) = schema,
      case .array(let enumValues) = obj["enum"]
    {
      return enumValues
    }
    return nil
  }

  private func enumStringValue(_ value: JSONValue) -> String? {
    if case .string(let str) = value {
      return str
    }
    return nil
  }

  private func extractStep(from schema: JSONValue) -> Double {
    if case .object(let obj) = schema {
      if case .number(let step) = obj["multipleOf"] {
        return step
      }
    }
    return 1.0
  }

  private func extractItems(from schema: JSONValue) -> JSONValue? {
    if case .object(let obj) = schema {
      return obj["items"]
    }
    return nil
  }

  private func extractProperties(from schema: JSONValue) -> [String: JSONValue]? {
    if case .object(let obj) = schema,
      case .object(let props) = obj["properties"]
    {
      return props
    }
    return nil
  }

  private func defaultValueForSchema(_ schema: JSONValue) -> JSONValue {
    guard let type = extractType(from: schema) else { return .null }

    switch type {
    case "string":
      // Check if this is an enum type
      if let enumValues = extractEnum(from: schema),
        let firstEnum = enumValues.first,
        case .string(let enumStr) = firstEnum
      {
        return .string(enumStr)
      }
      return .string("")
    case "number":
      return .number(0.0)
    case "integer":
      return .integer(0)
    case "boolean":
      return .boolean(false)
    case "array":
      return .array([])
    case "object":
      return .object([:])
    case "null":
      return .null
    default:
      return .null
    }
  }

  private func removeArrayItem() {
    guard let onRemoveArrayItem = onRemoveArrayItem else { return }
    onRemoveArrayItem()
  }

  private func valueToString(_ value: JSONValue) -> String {
    switch value {
    case .string(let str):
      return str
    case .number(let num):
      return String(num)
    case .integer(let int):
      return String(int)
    case .boolean(let bool):
      return String(bool)
    case .null:
      return "null"
    case .array:
      return "[Array]"
    case .object:
      return "{Object}"
    }
  }

  private func parseValue(_ string: String) -> JSONValue {
    if string.isEmpty || string == "null" {
      return .null
    } else if string == "true" {
      return .boolean(true)
    } else if string == "false" {
      return .boolean(false)
    } else if let int = Int64(string) {
      return .integer(int)
    } else if let num = Double(string) {
      return .number(num)
    } else {
      return .string(string)
    }
  }
}
