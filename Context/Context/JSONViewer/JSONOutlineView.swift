// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct JSONOutlineView: View {
  let jsonValue: JSONValue
  let searchText: String
  let isSearchActive: Bool
  @State private var selection = Set<JSONNode.ID>()
  @State private var rootNodes: [JSONNode] = []
  @State private var expandedNodes = Set<String>()
  @State private var flattenedNodes: [JSONNode] = []
  @State private var preSearchExpandedNodes: Set<String>?

  private func generateRootNodes() -> [JSONNode] {
    let rootNode = JSONNode(key: nil, value: jsonValue, keyPath: "", level: 0)
    // If root is a container, return its children directly to avoid extra nesting
    if rootNode.hasChildren {
      return createChildrenAtLevel(from: rootNode, startLevel: 0)
    } else {
      return [rootNode]
    }
  }

  private func createChildren(from node: JSONNode) -> [JSONNode] {
    return createChildrenAtLevel(from: node, startLevel: node.level + 1)
  }

  private func createChildrenAtLevel(from node: JSONNode, startLevel: Int) -> [JSONNode] {
    switch node.value {
    case .object(let dict):
      return dict.keys.sorted().map { key in
        JSONNode(
          key: key,
          value: dict[key]!,
          keyPath: node.keyPath.isEmpty ? key : "\(node.keyPath).\(key)",
          level: startLevel
        )
      }
    case .array(let array):
      return array.enumerated().map { index, value in
        JSONNode(
          key: "\(index)",
          value: value,
          keyPath: node.keyPath.isEmpty ? "\(index)" : "\(node.keyPath)[\(index)]",
          level: startLevel
        )
      }
    default:
      return []
    }
  }

  private func getNodesUpToLevel(_ maxLevel: Int, from nodes: [JSONNode]) -> Set<String> {
    var result = Set<String>()

    func traverse(_ nodes: [JSONNode]) {
      for node in nodes {
        if node.level < maxLevel && node.hasChildren {
          result.insert(node.id)
          let children = createChildren(from: node)
          traverse(children)
        }
      }
    }

    traverse(nodes)
    return result
  }

  private func updateFlattenedNodes() {
    var result: [JSONNode] = []

    func flatten(_ nodes: [JSONNode]) {
      for node in nodes {
        // During search, only show nodes that match or are ancestors/descendants of matches
        if !isSearchActive || shouldShowNodeInSearch(node) {
          result.append(node)
        }

        // Show children if node is expanded
        if expandedNodes.contains(node.id),
          let children = node.children(expandedNodes: expandedNodes)
        {
          flatten(children)
        }
      }
    }

    flatten(rootNodes)
    flattenedNodes = result
  }

  private func shouldShowNodeInSearch(_ node: JSONNode) -> Bool {
    // Show if node matches directly
    if nodeMatches(node) {
      return true
    }

    // Show if node has any descendant that matches
    if hasMatchingDescendant(node) {
      return true
    }

    // Show if node is a descendant of a matching ancestor
    if isDescendantOfMatch(node) {
      return true
    }

    return false
  }

  private func isDescendantOfMatch(_ targetNode: JSONNode) -> Bool {
    // Check if any ancestor of this node matches the search
    func checkAncestors(_ nodes: [JSONNode], targetPath: String) -> Bool {
      for node in nodes {
        // If this node matches and the target is a descendant
        if nodeMatches(node) && targetPath.hasPrefix(node.keyPath) && targetPath != node.keyPath {
          return true
        }

        // Recursively check children
        let children = createChildren(from: node)
        if checkAncestors(children, targetPath: targetPath) {
          return true
        }
      }
      return false
    }

    return checkAncestors(rootNodes, targetPath: targetNode.keyPath)
  }

  private func nodeMatches(_ node: JSONNode) -> Bool {
    let searchLower = searchText.lowercased()

    // Check key
    if let key = node.key, key.lowercased().contains(searchLower) {
      return true
    }

    // Check value
    let valueString = valueToString(node.value)
    if valueString.lowercased().contains(searchLower) {
      return true
    }

    return false
  }

  private func hasMatchingDescendant(_ node: JSONNode) -> Bool {
    let children = createChildren(from: node)
    for child in children {
      if nodeMatches(child) || hasMatchingDescendant(child) {
        return true
      }
    }
    return false
  }

  private func valueToString(_ value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case .boolean(let bool): return bool ? "true" : "false"
    case .integer(let int): return "\(int)"
    case .number(let double): return "\(double)"
    case .string(let string): return string
    case .object(_), .array(_): return ""
    }
  }

  private func capturePreSearchState() {
    if preSearchExpandedNodes == nil {
      preSearchExpandedNodes = expandedNodes
    }
  }

  private func restorePreSearchState() {
    if let savedState = preSearchExpandedNodes {
      expandedNodes = savedState
      preSearchExpandedNodes = nil
    }
  }

  private func expandNodesWithMatches() {
    if !isSearchActive {
      return
    }

    // Find all nodes that match and expand only the path to them (not the nodes themselves)
    func findAndExpandPathToMatches(_ nodes: [JSONNode], parentPath: [String] = []) {
      for node in nodes {
        let currentPath = parentPath + [node.id]

        // If this node matches, expand all ancestors in the path to make it visible
        // But do NOT expand the matching node itself
        if nodeMatches(node) {
          for ancestorId in parentPath {
            expandedNodes.insert(ancestorId)
          }
        }

        // Recursively check children
        let children = createChildren(from: node)
        findAndExpandPathToMatches(children, parentPath: currentPath)
      }
    }

    findAndExpandPathToMatches(rootNodes)
  }

  private func toggleExpansion(for nodeId: String) {
    if expandedNodes.contains(nodeId) {
      expandedNodes.remove(nodeId)
    } else {
      expandedNodes.insert(nodeId)
    }
    updateFlattenedNodes()
  }

  private func expandAll() {
    // Recursively find all nodes with children and add them to expandedNodes
    func collectAllExpandableNodes(_ nodes: [JSONNode]) -> Set<String> {
      var result = Set<String>()
      for node in nodes {
        if node.hasChildren {
          result.insert(node.id)
          let children = createChildren(from: node)
          result.formUnion(collectAllExpandableNodes(children))
        }
      }
      return result
    }

    expandedNodes = collectAllExpandableNodes(rootNodes)
    updateFlattenedNodes()
  }

  private func collapseAll() {
    expandedNodes.removeAll()
    updateFlattenedNodes()
  }

  @ViewBuilder
  private func nodeContextMenu(for node: JSONNode) -> some View {
    if node.hasChildren {
      if expandedNodes.contains(node.id) {
        Button("Collapse") {
          toggleExpansion(for: node.id)
        }
      } else {
        Button("Expand") {
          toggleExpansion(for: node.id)
        }
      }
      Divider()
    }
    Button("Copy JSON") {
      copyJSON(for: node.value)
    }
  }

  @ViewBuilder
  private func globalContextMenu() -> some View {
    Button("Expand All") {
      expandAll()
    }
    Button("Collapse All") {
      collapseAll()
    }
    Divider()
    Button("Copy JSON") {
      copyJSON(for: jsonValue)
    }
  }

  var body: some View {
    Table(flattenedNodes, selection: $selection) {
      TableColumn("Key") { node in
        HStack(spacing: 4) {
          // Indentation based on level (only for levels > 0)
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

          highlightedText(for: node.key ?? "root", searchText: isSearchActive ? searchText : "")
            .font(.system(.body, design: .monospaced))

          Spacer()
        }
        .contentShape(Rectangle())
      }
      .width(ideal: 200, max: 500)

      TableColumn("Type") { node in
        HStack {
          Text(typeText(for: node.value))
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.secondary)
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .width(min: 50, max: 80)

      TableColumn("Value") { node in
        HStack {
          if node.isContainer {
            Text(containerDescription(for: node.value))
              .font(.system(.body, design: .monospaced))
              .foregroundColor(.secondary)
          } else {
            highlightedValueText(for: node.value, searchText: isSearchActive ? searchText : "")
              .font(.system(.body, design: .monospaced))
          }
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .width(ideal: 400)
    }
    .contextMenu {
      globalContextMenu()
    }
    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    .onAppear {
      // Expand first 2 levels by default
      rootNodes = generateRootNodes()
      expandedNodes = getNodesUpToLevel(2, from: rootNodes)
      expandNodesWithMatches()
      updateFlattenedNodes()
    }
    .onChange(of: jsonValue) { _, _ in
      // Reset and expand first 2 levels for new JSON
      expandedNodes.removeAll()
      preSearchExpandedNodes = nil  // Clear any saved state
      rootNodes = generateRootNodes()
      expandedNodes = getNodesUpToLevel(2, from: rootNodes)
      expandNodesWithMatches()
      updateFlattenedNodes()
      selection.removeAll()
    }
    .onChange(of: isSearchActive) { oldValue, newValue in
      if !oldValue && newValue {
        // User started searching - capture current state
        capturePreSearchState()
        expandNodesWithMatches()
      } else if oldValue && !newValue {
        // User cleared search - restore original state
        restorePreSearchState()
      }
      updateFlattenedNodes()
    }
    .onChange(of: searchText) { _, _ in
      // Update filtering when search text changes (but search is still active)
      if isSearchActive {
        expandNodesWithMatches()
        updateFlattenedNodes()
      }
    }
    .contextMenu(forSelectionType: JSONNode.ID.self) { items in
      if let nodeID = items.first,
        let selectedNode = findNode(with: nodeID, in: rootNodes)
      {
        nodeContextMenu(for: selectedNode)
      } else if items.isEmpty && !selection.isEmpty,
        let selectedID = selection.first,
        let selectedNode = findNode(with: selectedID, in: rootNodes)
      {
        nodeContextMenu(for: selectedNode)
      } else {
        globalContextMenu()
      }
    }
  }

  private func typeText(for value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case .boolean(_): return "boolean"
    case .integer(_): return "integer"
    case .number(_): return "number"
    case .string(_): return "string"
    case .object(_): return "object"
    case .array(_): return "array"
    }
  }

  private func containerDescription(for value: JSONValue) -> String {
    switch value {
    case .object(let dict):
      let count = dict.count
      return "(\(count) item\(count == 1 ? "" : "s"))"
    case .array(let array):
      let count = array.count
      return "(\(count) item\(count == 1 ? "" : "s"))"
    default:
      return ""
    }
  }

  @ViewBuilder
  private func valueText(for value: JSONValue) -> some View {
    switch value {
    case .null:
      Text("null")
        .foregroundColor(.secondary)
    case .boolean(let bool):
      Text(bool ? "true" : "false")
        .foregroundColor(.primary)
    case .integer(let int):
      Text("\(int)")
        .foregroundColor(.primary)
    case .number(let double):
      Text("\(double)")
        .foregroundColor(.primary)
    case .string(let string):
      Text("\"\(string)\"")
        .foregroundColor(.primary)
    case .object(_), .array(_):
      EmptyView()
    }
  }

  private func findNode(with id: String, in nodes: [JSONNode]) -> JSONNode? {
    for node in nodes {
      if node.id == id {
        return node
      }
      if let children = node.children(expandedNodes: expandedNodes),
        let found = findNode(with: id, in: children)
      {
        return found
      }
    }
    return nil
  }

  private func copyJSON(for value: JSONValue) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    if let data = try? encoder.encode(value),
      let jsonString = String(data: data, encoding: .utf8)
    {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(jsonString, forType: .string)
    }
  }

  private func highlightedText(for text: String, searchText: String) -> Text {
    if searchText.isEmpty {
      return Text(text)
    }

    var attributedString = AttributedString(text)
    let searchLower = searchText.lowercased()
    let textLower = text.lowercased()

    // Find all ranges that match the search text
    var searchStartIndex = textLower.startIndex
    while searchStartIndex < textLower.endIndex {
      if let range = textLower.range(of: searchLower, range: searchStartIndex..<textLower.endIndex)
      {
        // Convert String range to AttributedString range
        let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString)!
        let upperBound = AttributedString.Index(range.upperBound, within: attributedString)!
        let attributedRange = lowerBound..<upperBound

        // Apply yellow background to the match
        attributedString[attributedRange].backgroundColor = .yellow.opacity(0.6)

        // Move to search after this match
        searchStartIndex = range.upperBound
      } else {
        break
      }
    }

    return Text(attributedString)
  }

  private func highlightedValueText(for value: JSONValue, searchText: String) -> Text {
    let valueString = valueToString(value)
    let baseText = highlightedText(for: valueString, searchText: searchText)

    // Apply value-specific formatting
    switch value {
    case .null:
      return baseText.foregroundColor(.secondary)
    case .boolean(_), .integer(_), .number(_), .string(_):
      return baseText.foregroundColor(.primary)
    case .object(_), .array(_):
      return Text("")  // This shouldn't happen for non-container values
    }
  }
}
