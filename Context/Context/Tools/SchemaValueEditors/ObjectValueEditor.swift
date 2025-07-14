// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct ObjectValueEditor: View {
  let node: SchemaNode
  @Binding var value: JSONValue
  @Binding var expandedNodes: Set<String>
  let isReadOnly: Bool
  let onValidate: () -> Void
  let onToggleExpansion: (String) -> Void
  var onNewPropertyAdded: ((String) -> Void)?
  
  var body: some View {
    Group {
      // Count both schema-defined and dynamic properties
      let (schemaCount, dynamicCount) = countObjectProperties()
      let totalCount = schemaCount + dynamicCount
      
      if totalCount > 0 {
        if dynamicCount > 0 {
          Text("\(schemaCount) defined, \(dynamicCount) dynamic")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.secondary)
        } else {
          Text("\(schemaCount) \(schemaCount == 1 ? "property" : "properties")")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.secondary)
        }
      } else {
        Text("No properties")
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  
  private func countObjectProperties() -> (schema: Int, dynamic: Int) {
    let schemaProperties = SchemaValueHelpers.extractProperties(from: node.schema) ?? [:]
    let schemaCount = schemaProperties.count
    
    var dynamicCount = 0
    if case .object(let valueObj) = value {
      // Count properties in the value that aren't in the schema
      dynamicCount = valueObj.keys.filter { !schemaProperties.keys.contains($0) }.count
    }
    
    return (schemaCount, dynamicCount)
  }
}