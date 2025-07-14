// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Dependencies
import SwiftUI

struct JSONSchemaEditor: View {
  let properties: [String: JSONValue]
  let required: Set<String>
  var rootSchema: JSONValue? = nil  // Full schema for resolving references

  @Binding var values: [String: JSONValue]
  @Binding var errors: [String: String]
  @Binding var focusedField: String?
  @Binding var dynamicPropertyTypes: [String: String]  // nodeId -> type (now a binding)
  @Binding var expandedNodes: Set<String>  // Make expansion state persistent
  @Binding var dynamicPropertyOrder: [String: [String]]  // parentId -> ordered property keys
  @FocusState private var internalFocusedField: String?

  @State private var flattenedNodes: [SchemaNode] = []
  @State private var editingKeys: [String: String] = [:]  // nodeId -> current editing key
  @State private var scrollToTop = UUID()
  @State private var schemaValidator = SchemaValidator()
  @AppStorage("JSONSchemaEditor.dividerPosition") private var persistedDividerPosition: Double =
  0.35
  @State private var dividerPosition: CGFloat? = nil  // Actual position in pixels
  @State private var initialDragPosition: CGFloat? = nil  // Track initial position for drag

  var body: some View {
    GeometryReader { geometry in
      let keyColumnWidth =
        dividerPosition ?? (geometry.size.width * CGFloat(persistedDividerPosition))

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(flattenedNodes) { node in
            HStack(spacing: 0) {
              // Key column
              nodeLabel(for: node)
                .frame(width: keyColumnWidth, height: rowHeight(for: node), alignment: .leading)
                .padding(.leading, 16)
                .padding(.trailing, 16)

              // Fixed divider space
              Color.clear
                .frame(width: 20)

              // Value and buttons
              HStack(spacing: 0) {
                nodeValueEditor(for: node)
                  .font(.system(size: 12))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.leading, 16)
                  .id(
                    node.isDynamic
                      ? "\(node.id)-\(dynamicPropertyTypes[node.id] ?? "string")" : node.id)

                // Buttons column
                nodeButtons(for: node)
                  .padding(.leading, 8)
                  .padding(.trailing, 16)
              }
            }
            .frame(height: rowHeight(for: node))
            .onAppear {
              if node.isDynamic && editingKeys[node.id] == nil {
                editingKeys[node.id] = node.key
              }
            }

            Divider()
              .opacity(0.5)
          }
        }
      }
      .background(Color(NSColor.controlBackgroundColor))
      .overlay(alignment: .topLeading) {
        // Visual divider line (no hit testing)
        Rectangle()
          .fill(Color(NSColor.separatorColor))
          .frame(width: 1, height: geometry.size.height)
          .offset(x: keyColumnWidth + 9.5)
          .allowsHitTesting(false)
      }
      .overlay(alignment: .topLeading) {
        // Drag handle with precise hit area
        Rectangle()
          .fill(Color.clear)
          .frame(width: 20, height: geometry.size.height)
          .contentShape(Rectangle())
          .offset(x: keyColumnWidth)
          .clipped()
          .onHover { hovering in
            if hovering {
              NSCursor.resizeLeftRight.push()
            } else {
              NSCursor.pop()
            }
          }
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                if initialDragPosition == nil {
                  initialDragPosition =
                    dividerPosition ?? (geometry.size.width * CGFloat(persistedDividerPosition))
                }

                if let startPos = initialDragPosition {
                  let minKeyWidth: CGFloat = 150
                  let minValueWidth: CGFloat = 500
                  // Max key width is limited by ensuring min value width
                  let maxKeyWidth = geometry.size.width - minValueWidth - 20  // 20 is divider space
                  let newPosition = max(
                    minKeyWidth, min(maxKeyWidth, startPos + value.translation.width))
                  dividerPosition = newPosition
                }
              }
              .onEnded { _ in
                if let finalPosition = dividerPosition {
                  // Save the position as a fraction of the total width
                  persistedDividerPosition = Double(finalPosition / geometry.size.width)
                }
                initialDragPosition = nil
              }
          )
      }
    }
    .id(scrollToTop)
    .onAppear(perform: handleOnAppear)
    .onChange(of: values) { _, _ in
      updateFlattenedNodes()
    }
    .onChange(of: properties) { _, _ in
      handlePropertiesChange()
    }
    .onChange(of: internalFocusedField) { _, newValue in
      focusedField = newValue
    }
    .onChange(of: focusedField) { _, newValue in
      internalFocusedField = newValue
    }
    .onChange(of: rootSchema) { _, newValue in
      schemaValidator.setRootSchema(newValue)
      updateFlattenedNodes()
    }
  }

  @ViewBuilder
  private func nodeButtons(for node: SchemaNode) -> some View {
    HStack(spacing: 4) {
      // Add button for arrays and objects
      // Use dynamic type if available, otherwise extract from schema
      let effectiveType =
        dynamicPropertyTypes[node.id] ?? SchemaValueHelpers.extractType(from: node.schema)
      if let schemaType = effectiveType {
        if schemaType == "array" {
          ArrayAddButton(
            node: node,
            value: nodeValueBinding(for: node),
            expandedNodes: $expandedNodes,
            isReadOnly: isReadOnly(node.schema),
            onValidate: { /* validation handled by SchemaValueEditor */  },
            onToggleExpansion: { toggleExpansion(for: $0) }
          )
        } else if schemaType == "object"
          && SchemaValueHelpers.allowsAdditionalProperties(node.schema)
        {
          Button(action: {
            addDynamicPropertyToObject(node)
          }) {
            Image(systemName: "plus.circle")
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
          .help("Add new property")
          .disabled(isReadOnly(node.schema))
        } else {
          // Spacer for alignment when no add button
          Color.clear
            .frame(width: 16, height: 16)
        }
      } else {
        // Spacer for alignment when no type
        Color.clear
          .frame(width: 16, height: 16)
      }

      // Remove button
      if (node.isArrayItem && SchemaValueHelpers.extractType(from: node.schema) != "array")
        || node.isDynamic
      {
        Button(action: {
          if node.isArrayItem {
            removeArrayItem(node)
          } else if node.isDynamic {
            removeDynamicProperty(node)
          }
        }) {
          Image(systemName: "minus.circle")
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
        .help(node.isDynamic ? "Remove this property" : "Remove this item")
        .disabled(isReadOnly(node.schema))
      } else {
        // Add spacer to maintain alignment when there's no button
        Color.clear
          .frame(width: 16, height: 16)
      }
    }
  }

  @ViewBuilder
  private func nodeLabel(for node: SchemaNode) -> some View {
    HStack(alignment: .center, spacing: 4) {
      nodeLevelIndentation(for: node)
      nodeExpandButton(for: node)
      nodeContent(for: node)
      Spacer()
    }
  }

  @ViewBuilder
  private func nodeLevelIndentation(for node: SchemaNode) -> some View {
    if node.level > 0 {
      HStack(spacing: 0) {
        ForEach(0..<node.level, id: \.self) { _ in
          Spacer()
            .frame(width: 20)
        }
      }
    }
  }

  @ViewBuilder
  private func nodeExpandButton(for node: SchemaNode) -> some View {
    let currentValue = getValueForNode(node)
    let shouldShowExpander = node.hasChildren || node.hasChildrenWithValue(currentValue)
    if shouldShowExpander {
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
  }

  @ViewBuilder
  private func nodeContent(for node: SchemaNode) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if node.isDynamic {
        dynamicPropertyField(for: node)
      } else {
        staticPropertyLabel(for: node)
      }

      nodeMetadata(for: node)

      if let comment = extractComment(from: node.schema) {
        Text(comment)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
          .truncationMode(.tail)
          .help(comment)
      }
    }
  }

  @ViewBuilder
  private func dynamicPropertyField(for node: SchemaNode) -> some View {
    TextField("Property name", text: dynamicPropertyBinding(for: node))
      .textFieldStyle(.plain)
      .font(.system(size: 12, design: .monospaced))
      .fontWeight(node.level == 0 ? .medium : .regular)
      .focused($internalFocusedField, equals: "\(node.id)-key")
      .onSubmit {
        commitDynamicPropertyEdit(for: node)
      }
      .onChange(of: internalFocusedField) { _, newValue in
        if newValue != "\(node.id)-key" {
          commitDynamicPropertyEdit(for: node)
        }
      }
  }

  private func dynamicPropertyBinding(for node: SchemaNode) -> Binding<String> {
    Binding(
      get: { editingKeys[node.id] ?? node.key },
      set: { editingKeys[node.id] = $0 }
    )
  }

  private func commitDynamicPropertyEdit(for node: SchemaNode) {
    if let editingKey = editingKeys[node.id], !editingKey.isEmpty {
      renameDynamicProperty(node, to: editingKey)
      editingKeys.removeValue(forKey: node.id)
    }
  }

  @ViewBuilder
  private func staticPropertyLabel(for node: SchemaNode) -> some View {
    HStack(spacing: 4) {
      Text(node.displayName)
        .font(
          .system(size: 12, design: extractTitle(from: node.schema) != nil ? .default : .monospaced)
        )
        .fontWeight(node.level == 0 ? .medium : .regular)

      if let title = extractTitle(from: node.schema), title != node.key {
        Text("(\(node.key))")
          .font(.caption2.monospaced())
          .foregroundColor(.secondary)
      }
    }
  }

  @ViewBuilder
  private func nodeMetadata(for node: SchemaNode) -> some View {
    HStack(spacing: 8) {
      if node.level == 0 && node.isRequired {
        Text("Required")
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      if isDeprecated(node.schema) {
        Text("Deprecated")
          .font(.caption2)
          .foregroundColor(.orange)
      }

      if isReadOnly(node.schema) {
        Text("Read-only")
          .font(.caption2)
          .foregroundColor(.blue)
      }
    }
  }

  private func nodeValueEditor(for node: SchemaNode) -> SchemaValueEditor {
    SchemaValueEditor(
      node: node,
      schemaValidator: schemaValidator,
      onToggleExpansion: { toggleExpansion(for: $0) },
      onRemoveArrayItem: removeItemAction(for: node),
      focusedField: $internalFocusedField,
      onNewPropertyAdded: handleNewPropertyAdded,
      onDynamicTypeChange: (node.isDynamic || (node.isArrayItem && !hasArrayItemSchema(node)))
        ? { newType in
          handleDynamicTypeChange(for: node, newType: newType)
        } : nil,
      selectedDynamicType: dynamicPropertyTypes[node.id],
      value: nodeValueBinding(for: node),
      expandedNodes: $expandedNodes,
      validationErrors: $errors
    )
  }

  private func nodeValueBinding(for node: SchemaNode) -> Binding<JSONValue> {
    Binding(
      get: { getValueForNode(node) },
      set: { setValueForNode(node, $0) }
    )
  }

  private func removeItemAction(for node: SchemaNode) -> (() -> Void)? {
    guard node.isArrayItem || node.isDynamic else { return nil }

    return {
      if node.isArrayItem {
        removeArrayItem(node)
      } else if node.isDynamic {
        removeDynamicProperty(node)
      }
    }
  }

  private func handleNewPropertyAdded(_ newNodeId: String) {
    updateFlattenedNodes()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      internalFocusedField = newNodeId
    }
  }

  private func handleDynamicTypeChange(for node: SchemaNode, newType: String) {
    // Store the new type for this dynamic property or array item
    dynamicPropertyTypes[node.id] = newType
    // Update the flattened nodes to reflect the new schema type
    updateFlattenedNodes()
  }

  private func handleOnAppear() {
    schemaValidator.setRootSchema(rootSchema)
    expandAllNodes()
    updateFlattenedNodes()
  }

  private func handlePropertiesChange() {
    // Don't clear expanded nodes - preserve expansion state
    // Only auto-expand nodes that aren't already expanded
    expandAllNodes()
    updateFlattenedNodes()
    scrollToTop = UUID()
  }

  private func rowHeight(for node: SchemaNode) -> CGFloat {
    // Base height for most fields
    var height: CGFloat = 36

    // Add extra height for fields with "Required" label
    if node.level == 0 && node.isRequired {
      height += 16
    }

    return height
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
            // Only expand if not already in the expanded set
            if !expandedNodes.contains(nodeId) {
              expandedNodes.insert(nodeId)
            }

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

    let rootNodes: [SchemaNode] = properties.keys.sorted().compactMap { key in
      guard let propSchema = properties[key] else { return nil }
      return SchemaNode(
        id: key,
        key: key,
        schema: schemaValidator.resolveSchema(propSchema),
        isRequired: required.contains(key),
        level: 0,
        path: [key]
      )
    }

    func flatten(_ nodes: [SchemaNode]) {
      for node in nodes {
        result.append(node)

        if expandedNodes.contains(node.id)
          && (node.hasChildren || node.hasChildrenWithValue(getValueForNode(node)))
        {
          let children = createChildren(from: node)
          flatten(children)
        }
      }
    }

    flatten(rootNodes)
    flattenedNodes = result

    // Clean up editing keys for nodes that no longer exist
    let currentNodeIds = Set(flattenedNodes.map { $0.id })
    editingKeys = editingKeys.filter { currentNodeIds.contains($0.key) }
    
    // Don't clean up dynamic types - we want to preserve them even for collapsed nodes
    // Only clean up types for nodes that truly don't exist anymore
    cleanupObsoleteDynamicTypes()
  }

  private func createChildren(from parent: SchemaNode) -> [SchemaNode] {
    // For dynamic properties, use the dynamic type first
    let schemaType = parent.dynamicType ?? extractType(from: parent.schema)
    guard let effectiveType = schemaType else { return [] }

    switch effectiveType {
    case "object":
      var children: [SchemaNode] = []

      // First, add schema-defined properties
      if let props = extractProperties(from: parent.schema) {
        let requiredSet = Set(extractRequired(from: parent.schema) ?? [])
        children += props.keys.sorted().compactMap { key in
          guard let propSchema = props[key] else { return nil }
          return SchemaNode(
            id: "\(parent.id).\(key)",
            key: key,
            schema: schemaValidator.resolveSchema(propSchema),
            isRequired: requiredSet.contains(key),
            level: parent.level + 1,
            path: parent.path + [key]
          )
        }
      }

      // Then, add dynamic properties from the value
      let currentValue = getValueForNode(parent)
      if case .object(let valueObj) = currentValue {
        let schemaProps = extractProperties(from: parent.schema) ?? [:]
        
        // Get dynamic keys and maintain their order
        let allDynamicKeys = valueObj.keys.filter { !schemaProps.keys.contains($0) }
        
        // Use stored order if available, otherwise use the current order
        let dynamicKeys: [String]
        if let storedOrder = dynamicPropertyOrder[parent.id] {
          // Filter stored order to only include keys that still exist
          let existingKeys = Set(allDynamicKeys)
          var orderedKeys = storedOrder.filter { existingKeys.contains($0) }
          
          // Add any new keys that aren't in the stored order at the end (sorted)
          let newKeys = allDynamicKeys.filter { !storedOrder.contains($0) }.sorted()
          orderedKeys.append(contentsOf: newKeys)
          
          dynamicKeys = orderedKeys
        } else {
          // First time seeing these properties - sort them for consistent order
          dynamicKeys = allDynamicKeys.sorted()
          dynamicPropertyOrder[parent.id] = dynamicKeys
        }

        // Get the additionalProperties schema
        let additionalPropsSchema = extractAdditionalProperties(from: parent.schema)

        children += dynamicKeys.map { key in
          let nodeId = "\(parent.id).\(key)"
          let dynamicSchema: JSONValue

          // First check if user has selected a type
          if let storedType = dynamicPropertyTypes[nodeId] {
            // User has explicitly selected a type - use it
            dynamicSchema = createSchemaForType(storedType)
          } else if let additionalPropsSchema = additionalPropsSchema,
            case .object = additionalPropsSchema
          {
            // Use the provided schema for additional properties
            dynamicSchema = additionalPropsSchema
          } else {
            // Infer schema from the actual value
            let propertyValue = valueObj[key] ?? .null
            dynamicSchema = createSchemaForValue(propertyValue)
            
            // Only store inferred type if we don't have one already
            if dynamicPropertyTypes[nodeId] == nil {
              switch propertyValue {
              case .array:
                dynamicPropertyTypes[nodeId] = "array"
              case .object:
                dynamicPropertyTypes[nodeId] = "object"
              default:
                break
              }
            }
          }

          return SchemaNode(
            id: nodeId,
            key: key,
            schema: dynamicSchema,
            isRequired: false,
            level: parent.level + 1,
            path: parent.path + [key],
            isDynamic: true,
            dynamicType: dynamicPropertyTypes[nodeId]
          )
        }
      }

      return children
    case "array":
      let currentValue = getValueForNode(parent)
      if case .array(let items) = currentValue {
        let prefixItems = extractPrefixItems(from: parent.schema)
        let itemsSchema = extractItems(from: parent.schema)
        let additionalItemsSchema = extractAdditionalItems(from: parent.schema)

        return items.enumerated().map { index, itemValue in
          let nodeId = "\(parent.id)[\(index)]"
          let itemSchema: JSONValue
          let isDynamicItem: Bool

          // Check for prefix items first (tuple validation)
          if let prefixItems = prefixItems, index < prefixItems.count {
            // Use the schema from prefixItems for tuple validation
            itemSchema = schemaValidator.resolveSchema(prefixItems[index])
            isDynamicItem = false
          } else if let additionalItemsSchema = additionalItemsSchema, prefixItems != nil {
            // Use additionalItems schema for items beyond the tuple
            itemSchema = schemaValidator.resolveSchema(additionalItemsSchema)
            isDynamicItem = false
          } else if let itemsSchema = itemsSchema {
            // Check if the items schema is effectively empty
            let resolvedItemsSchema = schemaValidator.resolveSchema(itemsSchema)
            let isEmptySchema = isEffectivelyEmptySchema(resolvedItemsSchema)
            
            if isEmptySchema {
              // Treat empty schemas as dynamic
              isDynamicItem = true
              
              itemSchema = inferDynamicItemSchema(for: nodeId, itemValue: itemValue)
            } else {
              // Use the actual items schema
              itemSchema = resolvedItemsSchema
              isDynamicItem = false
            }
          } else {
            // No schema specified - treat as dynamic like object properties
            isDynamicItem = true
            itemSchema = inferDynamicItemSchema(for: nodeId, itemValue: itemValue)
          }

          return SchemaNode(
            id: nodeId,
            key: "[\(index)]",
            schema: itemSchema,
            isRequired: false,
            level: parent.level + 1,
            path: parent.path + ["[\(index)]"],
            isArrayItem: true,
            arrayIndex: index,
            isDynamic: isDynamicItem,
            dynamicType: isDynamicItem ? dynamicPropertyTypes[nodeId] : nil
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
    // Handle boolean schemas
    if case .boolean(let bool) = schema {
      return bool ? nil : "never"
    }

    if case .object(let obj) = schema,
      case .string(let typeStr) = obj["type"]
    {
      return typeStr
    }
    return nil
  }

  private func extractProperties(from schema: JSONValue) -> [String: JSONValue]? {
    // Boolean schemas don't have properties
    if case .boolean = schema {
      return nil
    }

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

  private func extractPrefixItems(from schema: JSONValue) -> [JSONValue]? {
    if case .object(let obj) = schema,
      case .array(let prefixItems) = obj["prefixItems"]
    {
      return prefixItems
    }
    return nil
  }

  private func extractAdditionalItems(from schema: JSONValue) -> JSONValue? {
    if case .object(let obj) = schema {
      return obj["additionalItems"]
    }
    return nil
  }

  private func extractAdditionalProperties(from schema: JSONValue) -> JSONValue? {
    if case .object(let obj) = schema {
      return obj["additionalProperties"]
    }
    return nil
  }

  private func createSchemaForValue(_ value: JSONValue) -> JSONValue {
    switch value {
    case .string:
      return .object(["type": .string("string")])
    case .number:
      return .object(["type": .string("number")])
    case .integer:
      return .object(["type": .string("integer")])
    case .boolean:
      return .object(["type": .string("boolean")])
    case .array:
      return .object(["type": .string("array"), "items": .object([:])])
    case .object:
      return .object(["type": .string("object"), "properties": .object([:])])
    case .null:
      return .object(["type": .string("string")])  // Default to string for null values
    }
  }

  private func createSchemaForType(_ type: String) -> JSONValue {
    let schema: JSONValue
    switch type {
    case "array":
      schema = .object(["type": .string("array"), "items": .object([:])])
    case "object":
      schema = .object(["type": .string("object"), "properties": .object([:])])
    default:
      schema = .object(["type": .string(type)])
    }
    return schema
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

    // Clean up the dynamic type for this array item
    dynamicPropertyTypes.removeValue(forKey: node.id)
    
    // Also need to clean up types for items after this index as they will shift
    cleanupArrayItemTypes(parentPath: parentPath, removedIndex: arrayIndex)

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

  private func removeDynamicProperty(_ node: SchemaNode) {
    guard node.isDynamic && node.path.count >= 2 else { return }

    let parentPath = Array(node.path.dropLast())
    guard let propertyKey = node.path.last else { return }

    if parentPath.count == 1 {
      // Direct child of root
      let rootKey = parentPath[0]
      if case .object(var rootObj) = values[rootKey] {
        rootObj.removeValue(forKey: propertyKey)
        values[rootKey] = .object(rootObj)
      }
    } else {
      // Nested property
      let rootKey = parentPath[0]
      var rootValue = values[rootKey] ?? .null
      rootValue = removeDynamicPropertyAtPath(
        rootValue, at: Array(parentPath.dropFirst()), propertyKey: propertyKey)
      values[rootKey] = rootValue
    }
    
    // Update the property order to remove the deleted property
    let parentId = parentPath.count == 1 ? parentPath[0] : "\(parentPath.joined(separator: "."))"
    if var order = dynamicPropertyOrder[parentId] {
      order.removeAll { $0 == propertyKey }
      dynamicPropertyOrder[parentId] = order
    }

    updateFlattenedNodes()
  }

  private func removeDynamicPropertyAtPath(
    _ value: JSONValue, at path: [String], propertyKey: String
  ) -> JSONValue {
    if path.isEmpty {
      if case .object(var obj) = value {
        obj.removeValue(forKey: propertyKey)
        return .object(obj)
      }
      return value
    }

    let component = path[0]
    let remainingPath = Array(path.dropFirst())

    if component.hasPrefix("[") && component.hasSuffix("]") {
      // Array index
      let indexStr = String(component.dropFirst().dropLast())
      if let idx = Int(indexStr), case .array(var arr) = value, idx < arr.count {
        arr[idx] = removeDynamicPropertyAtPath(
          arr[idx], at: remainingPath, propertyKey: propertyKey)
        return .array(arr)
      }
    } else {
      if case .object(var obj) = value {
        if let propValue = obj[component] {
          obj[component] = removeDynamicPropertyAtPath(
            propValue, at: remainingPath, propertyKey: propertyKey)
        }
        return .object(obj)
      }
    }

    return value
  }

  private func renameDynamicProperty(_ node: SchemaNode, to newKey: String) {
    guard node.isDynamic && !newKey.isEmpty && newKey != node.key else { return }

    // Get the parent path
    let parentPath = Array(node.path.dropLast())
    let oldKey = node.key

    var renameSuccessful = false

    if parentPath.count == 1 {
      // Direct child of root
      let rootKey = parentPath[0]
      if case .object(var rootObj) = values[rootKey] {
        // Check if new key already exists
        if rootObj.keys.contains(newKey) {
          // Don't rename if key already exists
          errors[node.id] = "Property '\(newKey)' already exists"
          return
        }

        // Get the value and remove old key
        if let value = rootObj[oldKey] {
          rootObj.removeValue(forKey: oldKey)
          rootObj[newKey] = value
          values[rootKey] = .object(rootObj)
          renameSuccessful = true
        }
      }
    } else {
      // Nested property
      let rootKey = parentPath[0]
      let rootValue = values[rootKey] ?? .null
      let (newValue, success) = renameDynamicPropertyAtPath(
        rootValue, at: Array(parentPath.dropFirst()), oldKey: oldKey, newKey: newKey)
      if success {
        values[rootKey] = newValue
        renameSuccessful = true
      } else {
        errors[node.id] = "Property '\(newKey)' already exists"
      }
    }

    if renameSuccessful {
      // Clear any error
      errors.removeValue(forKey: node.id)
      
      // Update the property order to reflect the rename
      let parentId = parentPath.isEmpty ? "" : (parentPath.count == 1 ? parentPath[0] : "\(parentPath.joined(separator: "."))")
      if var order = dynamicPropertyOrder[parentId] {
        if let index = order.firstIndex(of: oldKey) {
          order[index] = newKey
          dynamicPropertyOrder[parentId] = order
        }
      }
      
      updateFlattenedNodes()
    }
  }

  private func renameDynamicPropertyAtPath(
    _ value: JSONValue, at path: [String], oldKey: String, newKey: String
  ) -> (JSONValue, Bool) {
    if path.isEmpty {
      if case .object(var obj) = value {
        // Check if new key already exists
        if obj.keys.contains(newKey) {
          return (value, false)
        }

        if let propValue = obj[oldKey] {
          obj.removeValue(forKey: oldKey)
          obj[newKey] = propValue
        }
        return (.object(obj), true)
      }
      return (value, false)
    }

    let component = path[0]
    let remainingPath = Array(path.dropFirst())

    if component.hasPrefix("[") && component.hasSuffix("]") {
      // Array index
      let indexStr = String(component.dropFirst().dropLast())
      if let idx = Int(indexStr), case .array(var arr) = value, idx < arr.count {
        let (newValue, success) = renameDynamicPropertyAtPath(
          arr[idx], at: remainingPath, oldKey: oldKey, newKey: newKey)
        if success {
          arr[idx] = newValue
          return (.array(arr), true)
        }
        return (value, false)
      }
    } else {
      if case .object(var obj) = value {
        if let propValue = obj[component] {
          let (newValue, success) = renameDynamicPropertyAtPath(
            propValue, at: remainingPath, oldKey: oldKey, newKey: newKey)
          if success {
            obj[component] = newValue
            return (.object(obj), true)
          }
        }
        return (value, false)
      }
    }

    return (value, false)
  }

  private func isDeprecated(_ schema: JSONValue) -> Bool {
    if case .object(let obj) = schema,
      case .boolean(true) = obj["deprecated"]
    {
      return true
    }
    return false
  }

  private func isReadOnly(_ schema: JSONValue) -> Bool {
    if case .object(let obj) = schema,
      case .boolean(true) = obj["readOnly"]
    {
      return true
    }
    return false
  }

  private func extractTitle(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let title) = obj["title"]
    {
      return title
    }
    return nil
  }

  private func extractComment(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let comment) = obj["$comment"]
    {
      return comment
    }
    return nil
  }

  private func addDynamicPropertyToObject(_ node: SchemaNode) {
    let currentValue = getValueForNode(node)

    if case .object(var obj) = currentValue {
      // Generate a unique property name
      var newPropName = "newProperty"
      var counter = 1
      while obj.keys.contains(newPropName) {
        newPropName = "newProperty\(counter)"
        counter += 1
      }

      // Always start with empty string for new properties
      obj[newPropName] = .string("")
      setValueForNode(node, .object(obj))
      
      // Update the dynamic property order to include the new property at the end
      var currentOrder = dynamicPropertyOrder[node.id] ?? []
      if !currentOrder.contains(newPropName) {
        currentOrder.append(newPropName)
        dynamicPropertyOrder[node.id] = currentOrder
      }

      // Auto-expand and focus
      if !expandedNodes.contains(node.id) {
        toggleExpansion(for: node.id)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        internalFocusedField = "\(node.id).\(newPropName)-key"
      }
    }
  }

  private func cleanupObsoleteDynamicTypes() {
    // Build a set of all possible node IDs that could exist (including collapsed ones)
    var allPossibleNodeIds = Set<String>()
    
    func collectAllPossibleIds(from properties: [String: JSONValue], parentId: String = "") {
      for (key, schema) in properties {
        let nodeId = parentId.isEmpty ? key : "\(parentId).\(key)"
        allPossibleNodeIds.insert(nodeId)
        
        // Check if this could have children
        if let type = extractType(from: schema) {
          if type == "object", let nestedProps = extractProperties(from: schema) {
            collectAllPossibleIds(from: nestedProps, parentId: nodeId)
          } else if type == "array" {
            // For arrays, check actual values to see what items exist
            let path = parentId.isEmpty ? [key] : parentId.split(separator: ".").map(String.init) + [key]
            let value = getValueForNode(SchemaNode(id: nodeId, key: key, schema: schema, isRequired: false, level: 0, path: path))
            if case .array(let items) = value {
              for index in 0..<items.count {
                allPossibleNodeIds.insert("\(nodeId)[\(index)]")
              }
            }
          }
        }
        
        // Also check dynamic properties from actual values
        let path = parentId.isEmpty ? [key] : parentId.split(separator: ".").map(String.init) + [key]
        let value = getValueForNode(SchemaNode(id: nodeId, key: key, schema: schema, isRequired: false, level: 0, path: path))
        if case .object(let obj) = value {
          let schemaProps = extractProperties(from: schema) ?? [:]
          for dynamicKey in obj.keys where !schemaProps.keys.contains(dynamicKey) {
            allPossibleNodeIds.insert("\(nodeId).\(dynamicKey)")
          }
        }
      }
    }
    
    collectAllPossibleIds(from: properties)
    
    // Only remove types for nodes that don't exist at all
    dynamicPropertyTypes = dynamicPropertyTypes.filter { allPossibleNodeIds.contains($0.key) }
  }

  private func hasArrayItemSchema(_ node: SchemaNode) -> Bool {
    // Check if this array item has a defined schema from the array's items property
    guard node.isArrayItem else { return false }

    // Find the parent array node by removing the last path component (the index)
    let parentPath = Array(node.path.dropLast())
    if parentPath.isEmpty { return false }

    // Get the parent array's schema
    var parentSchema: JSONValue = .null
    if parentPath.count == 1 {
      parentSchema = properties[parentPath[0]] ?? .null
    } else {
      // Navigate to nested schema
      parentSchema = properties[parentPath[0]] ?? .null
      for component in parentPath.dropFirst() {
        if case .object(let obj) = parentSchema,
          let nestedSchema = obj[component]
        {
          parentSchema = nestedSchema
        }
      }
    }

    // Check if the parent array has an items schema that's not empty
    if let itemsSchema = SchemaValueHelpers.extractItems(from: schemaValidator.resolveSchema(parentSchema)) {
      return !isEffectivelyEmptySchema(itemsSchema)
    }
    return false
  }

  private func isEffectivelyEmptySchema(_ schema: JSONValue) -> Bool {
    // Check if a schema is effectively empty (just an empty object with no constraints)
    if case .object(let obj) = schema {
      // An empty object schema {} or one with only metadata fields is effectively empty
      let significantKeys = obj.keys.filter { key in
        // Filter out metadata fields that don't affect validation
        !["$id", "$schema", "$ref", "$comment", "title", "description", "examples", "default"].contains(key)
      }
      return significantKeys.isEmpty
    }
    return false
  }

  private func inferDynamicItemSchema(for nodeId: String, itemValue: JSONValue) -> JSONValue {
    // Check if user has selected a type for this item
    if let storedType = dynamicPropertyTypes[nodeId] {
      // Use the user-selected type
      return createSchemaForType(storedType)
    } else {
      // Infer from value
      let schema = createSchemaForValue(itemValue)
      
      // Store inferred type if we don't have one already
      if dynamicPropertyTypes[nodeId] == nil {
        switch itemValue {
        case .array:
          dynamicPropertyTypes[nodeId] = "array"
        case .object:
          dynamicPropertyTypes[nodeId] = "object"
        default:
          // Don't infer type for null or other values - let user choose
          break
        }
      }
      
      return schema
    }
  }

  private func cleanupArrayItemTypes(parentPath: [String], removedIndex: Int) {
    // Get the parent array's node ID
    let parentId = parentPath.joined(separator: ".")
    
    // Find all dynamic types for items after the removed index
    var updates: [(oldKey: String, newKey: String)] = []
    
    for (nodeId, _) in dynamicPropertyTypes {
      if nodeId.hasPrefix("\(parentId)[") && nodeId.hasSuffix("]") {
        // Extract the index from nodeId like "parent[2]"
        let startIndex = nodeId.index(nodeId.startIndex, offsetBy: parentId.count + 1)
        let endIndex = nodeId.index(nodeId.endIndex, offsetBy: -1)
        if let index = Int(nodeId[startIndex..<endIndex]), index > removedIndex {
          let newNodeId = "\(parentId)[\(index - 1)]"
          updates.append((oldKey: nodeId, newKey: newNodeId))
        }
      }
    }
    
    // Apply the updates
    for update in updates {
      if let type = dynamicPropertyTypes[update.oldKey] {
        dynamicPropertyTypes.removeValue(forKey: update.oldKey)
        dynamicPropertyTypes[update.newKey] = type
      }
    }
  }
}
