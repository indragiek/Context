// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct ArrayAddButton: View {
  let node: SchemaNode
  @Binding var value: JSONValue
  @Binding var expandedNodes: Set<String>
  let isReadOnly: Bool
  let onValidate: () -> Void
  let onToggleExpansion: (String) -> Void
  
  var body: some View {
    // Check what types are allowed for array items
    if let allowedTypes = getAllowedTypes() {
      if allowedTypes.count == 1 {
        // Single type - direct add button
        Button(action: {
          addItem(withType: allowedTypes[0])
        }) {
          Image(systemName: "plus.circle")
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .help("Add new \(allowedTypes[0]) item")
        .disabled(isReadOnly)
      } else if allowedTypes.count > 1 {
        // Multiple types - show type selector
        Menu {
          ForEach(allowedTypes, id: \.self) { type in
            Button(action: {
              addItem(withType: type)
            }) {
              Text(typeDisplayName(type))
            }
          }
        } label: {
          Image(systemName: "plus.circle")
            .foregroundColor(.accentColor)
        }
        .menuStyle(.borderlessButton)
        .help("Add new item")
        .disabled(isReadOnly)
      } else {
        // No specific types - allow any type
        Menu {
          ForEach(["string", "number", "integer", "boolean", "object", "array", "null"], id: \.self) { type in
            Button(action: {
              addItem(withType: type)
            }) {
              Text(typeDisplayName(type))
            }
          }
        } label: {
          Image(systemName: "plus.circle")
            .foregroundColor(.accentColor)
        }
        .menuStyle(.borderlessButton)
        .help("Add new item")
        .disabled(isReadOnly)
      }
    } else {
      // No schema - default behavior
      Button(action: {
        addDefaultItem()
      }) {
        Image(systemName: "plus.circle")
          .foregroundColor(.accentColor)
      }
      .buttonStyle(.plain)
      .help("Add new item")
      .disabled(isReadOnly)
    }
  }
  
  private func getAllowedTypes() -> [String]? {
    // Check if the array schema specifies item types
    if let itemsSchema = SchemaValueHelpers.extractItems(from: node.schema) {
      // Check if items schema has a type
      if let types = SchemaValueHelpers.extractTypes(from: itemsSchema) {
        return types
      } else if let type = SchemaValueHelpers.extractType(from: itemsSchema) {
        return [type]
      }
    }
    return nil
  }
  
  private func typeDisplayName(_ type: String) -> String {
    switch type {
    case "string": return "String"
    case "number": return "Number"
    case "integer": return "Integer"
    case "boolean": return "Boolean"
    case "array": return "Array"
    case "object": return "Object"
    case "null": return "Null"
    default: return type.capitalized
    }
  }
  
  private func addItem(withType type: String) {
    let newValue = SchemaValueHelpers.defaultValueForType(type, isRequired: true)
    
    if case .array(var items) = value {
      items.append(newValue)
      value = .array(items)
    } else {
      value = .array([newValue])
    }
    onValidate()
    // Auto-expand this node to show the new item
    if !expandedNodes.contains(node.id) {
      onToggleExpansion(node.id)
    }
  }
  
  private func addDefaultItem() {
    // Default behavior for arrays without schema - start with string
    let defaultValue: JSONValue
    if let itemsSchema = SchemaValueHelpers.extractItems(from: node.schema) {
      // Check if the items schema actually specifies a type
      if SchemaValueHelpers.extractType(from: itemsSchema) != nil {
        // Use the schema if it has a specific type
        defaultValue = SchemaValueHelpers.defaultValueForSchema(itemsSchema, isRequired: true)
      } else {
        // Items schema exists but doesn't specify a type (e.g., empty object {}) - default to string
        defaultValue = .string("")
      }
    } else {
      // No schema - default to empty string (not null)
      defaultValue = .string("")
    }
    
    if case .array(var items) = value {
      items.append(defaultValue)
      value = .array(items)
    } else {
      value = .array([defaultValue])
    }
    onValidate()
    // Auto-expand this node to show the new item
    if !expandedNodes.contains(node.id) {
      onToggleExpansion(node.id)
    }
  }
}