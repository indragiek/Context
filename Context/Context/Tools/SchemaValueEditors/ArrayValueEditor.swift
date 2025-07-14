// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct ArrayValueEditor: View {
  let node: SchemaNode
  @Binding var value: JSONValue
  @Binding var expandedNodes: Set<String>
  let isReadOnly: Bool
  let onValidate: () -> Void
  let onToggleExpansion: (String) -> Void
  
  var body: some View {
    Group {
      if case .array(let items) = value {
        Text("\(items.count) \(items.count == 1 ? "item" : "items")")
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
      } else {
        Text("Empty array")
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}