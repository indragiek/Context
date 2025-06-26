// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct JSONSchemaEditor: View {
  let properties: [String: JSONValue]
  let required: Set<String>
  @Binding var values: [String: JSONValue]
  @Binding var errors: [String: String]
  @Binding var focusedField: String?

  @State private var expandedNodes = Set<String>()
  @State private var flattenedNodes: [SchemaNode] = []
  @FocusState private var internalFocusedField: String?

  @State private var scrollToTop = UUID()

  var body: some View {
    Table(flattenedNodes) {
      TableColumn("Argument") { node in
        HStack(spacing: 4) {
          if node.level > 0 {
            HStack(spacing: 0) {
              ForEach(0..<node.level, id: \.self) { _ in
                Spacer()
                  .frame(width: 20)
              }
            }
          }

          if node.hasChildren {
            Button(action: {
              toggleExpansion(for: node.id)
            }) {
              Image(systemName: expandedNodes.contains(node.id) ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          } else {
            Spacer()
              .frame(width: 20)
          }

          Text(node.displayName)
            .font(.system(size: 12, design: .monospaced))
            .fontWeight(node.level == 0 ? .medium : .regular)

          Spacer()
        }
      }

      TableColumn("Value") { node in
        SchemaValueEditor(
          node: node,
          value: Binding(
            get: { getValueForNode(node) },
            set: { setValueForNode(node, $0) }
          ),
          expandedNodes: $expandedNodes,
          onToggleExpansion: { toggleExpansion(for: $0) },
          onRemoveArrayItem: node.isArrayItem
            ? {
              removeArrayItem(node)
            } : nil,
          focusedField: $internalFocusedField,
          onTabPressed: {
            moveToNextField(from: node)
          }
        )
        .font(.system(size: 12))
      }

      TableColumn("") { node in
        if node.level == 0 && node.isRequired {
          Text("Required")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.trailing, 8)
        } else {
          EmptyView()
        }
      }
      .width(80)
    }
    .frame(minHeight: 100)
    .id(scrollToTop)
    .onAppear {
      expandAllNodes()
      updateFlattenedNodes()
    }
    .onChange(of: values) { _, _ in
      updateFlattenedNodes()
    }
    .onChange(of: properties) { _, _ in
      expandedNodes.removeAll()
      expandAllNodes()
      updateFlattenedNodes()
      scrollToTop = UUID()
    }
    .onChange(of: internalFocusedField) { _, newValue in
      focusedField = newValue
    }
    .onChange(of: focusedField) { _, newValue in
      internalFocusedField = newValue
    }
  }

  private func toggleExpansion(for nodeId: String) {
    if expandedNodes.contains(nodeId) {
      expandedNodes.remove(nodeId)
    } else {
      expandedNodes.insert(nodeId)
    }
    updateFlattenedNodes()
  }

  private func expandAllNodes() {
    func collectExpandableNodes(from properties: [String: JSONValue], parentId: String = "") {
      for (key, schema) in properties {
        let nodeId = parentId.isEmpty ? key : "\(parentId).\(key)"

        if let type = extractType(from: schema) {
          if type == "object" || type == "array" {
            expandedNodes.insert(nodeId)

            if type == "object", let nestedProps = extractProperties(from: schema) {
              collectExpandableNodes(from: nestedProps, parentId: nodeId)
            }
          }
        }
      }
    }

    collectExpandableNodes(from: properties)
  }

  private func updateFlattenedNodes() {
    var result: [SchemaNode] = []

    let rootNodes = properties.keys.sorted().map { key in
      SchemaNode(
        id: key,
        key: key,
        schema: properties[key]!,
        isRequired: required.contains(key),
        level: 0,
        path: [key]
      )
    }

    func flatten(_ nodes: [SchemaNode]) {
      for node in nodes {
        result.append(node)

        if expandedNodes.contains(node.id) && node.hasChildren {
          let children = createChildren(from: node)
          flatten(children)
        }
      }
    }

    flatten(rootNodes)
    flattenedNodes = result
  }

  private func createChildren(from parent: SchemaNode) -> [SchemaNode] {
    guard let schemaType = extractType(from: parent.schema) else { return [] }

    switch schemaType {
    case "object":
      if let props = extractProperties(from: parent.schema) {
        let requiredSet = Set(extractRequired(from: parent.schema) ?? [])
        return props.keys.sorted().map { key in
          SchemaNode(
            id: "\(parent.id).\(key)",
            key: key,
            schema: props[key]!,
            isRequired: requiredSet.contains(key),
            level: parent.level + 1,
            path: parent.path + [key]
          )
        }
      }
    case "array":
      let currentValue = getValueForNode(parent)
      if case .array(let items) = currentValue {
        return items.enumerated().map { index, _ in
          let itemSchema = extractItems(from: parent.schema) ?? .object([:])
          return SchemaNode(
            id: "\(parent.id)[\(index)]",
            key: "[\(index)]",
            schema: itemSchema,
            isRequired: false,
            level: parent.level + 1,
            path: parent.path + ["[\(index)]"],
            isArrayItem: true,
            arrayIndex: index
          )
        }
      }
    default:
      break
    }

    return []
  }

  private func getValueForNode(_ node: SchemaNode) -> JSONValue {
    if node.path.isEmpty { return .null }

    var current = values[node.path[0]] ?? .null

    for i in 1..<node.path.count {
      let component = node.path[i]

      if component.hasPrefix("[") && component.hasSuffix("]") {
        let indexStr = String(component.dropFirst().dropLast())
        if let index = Int(indexStr),
          case .array(let arr) = current,
          index < arr.count
        {
          current = arr[index]
        } else {
          return .null
        }
      } else {
        if case .object(let obj) = current {
          current = obj[component] ?? .null
        } else {
          return .null
        }
      }
    }

    return current
  }

  private func setValueForNode(_ node: SchemaNode, _ newValue: JSONValue) {
    if node.path.isEmpty { return }

    if node.path.count == 1 {
      values[node.path[0]] = newValue
      return
    }

    let rootKey = node.path[0]
    var rootValue = values[rootKey] ?? .null

    rootValue = updateNestedValue(rootValue, at: Array(node.path.dropFirst()), with: newValue)
    values[rootKey] = rootValue
  }

  private func updateNestedValue(_ value: JSONValue, at path: [String], with newValue: JSONValue)
    -> JSONValue
  {
    if path.isEmpty {
      return newValue
    }

    let component = path[0]
    let remainingPath = Array(path.dropFirst())

    if component.hasPrefix("[") && component.hasSuffix("]") {
      // Array index
      let indexStr = String(component.dropFirst().dropLast())
      if let index = Int(indexStr),
        case .array(var arr) = value
      {
        if index < arr.count {
          arr[index] = updateNestedValue(arr[index], at: remainingPath, with: newValue)
        }
        return .array(arr)
      }
    } else {
      if case .object(var obj) = value {
        obj[component] = updateNestedValue(
          obj[component] ?? .null, at: remainingPath, with: newValue)
        return .object(obj)
      } else if path.count == 1 {
        return .object([component: newValue])
      }
    }

    return value
  }

  private func extractType(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let typeStr) = obj["type"]
    {
      return typeStr
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

  private func extractRequired(from schema: JSONValue) -> [String]? {
    if case .object(let obj) = schema,
      case .array(let req) = obj["required"]
    {
      return req.compactMap {
        if case .string(let str) = $0 { return str }
        return nil
      }
    }
    return nil
  }

  private func extractItems(from schema: JSONValue) -> JSONValue? {
    if case .object(let obj) = schema {
      return obj["items"]
    }
    return nil
  }

  private func removeArrayItem(_ node: SchemaNode) {
    guard node.isArrayItem, let arrayIndex = node.arrayIndex else { return }

    let parentPath = Array(node.path.dropLast())
    guard !parentPath.isEmpty else { return }

    let rootKey = parentPath[0]
    var rootValue = values[rootKey] ?? .null

    rootValue = removeArrayItemAtPath(
      rootValue, at: Array(parentPath.dropFirst()), index: arrayIndex)
    values[rootKey] = rootValue

    updateFlattenedNodes()
  }

  private func removeArrayItemAtPath(_ value: JSONValue, at path: [String], index: Int) -> JSONValue
  {
    if path.isEmpty {
      if case .array(var arr) = value, index < arr.count {
        arr.remove(at: index)
        return .array(arr)
      }
      return value
    }

    let component = path[0]
    let remainingPath = Array(path.dropFirst())

    if component.hasPrefix("[") && component.hasSuffix("]") {
      // Array index
      let indexStr = String(component.dropFirst().dropLast())
      if let idx = Int(indexStr), case .array(var arr) = value, idx < arr.count {
        arr[idx] = removeArrayItemAtPath(arr[idx], at: remainingPath, index: index)
        return .array(arr)
      }
    } else {
      if case .object(var obj) = value {
        if let propValue = obj[component] {
          obj[component] = removeArrayItemAtPath(propValue, at: remainingPath, index: index)
        }
        return .object(obj)
      }
    }

    return value
  }

  private func moveToNextField(from currentNode: SchemaNode) {
    let editableNodes = flattenedNodes.filter { node in
      if let type = extractType(from: node.schema) {
        return type == "string" || type == "number" || type == "integer"
      }
      return false
    }

    if let currentIndex = editableNodes.firstIndex(where: { $0.id == currentNode.id }) {
      let nextIndex = (currentIndex + 1) % editableNodes.count
      internalFocusedField = editableNodes[nextIndex].id
    }
  }
}
