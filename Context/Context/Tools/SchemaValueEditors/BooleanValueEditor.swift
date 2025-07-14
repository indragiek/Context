// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct BooleanValueEditor: View {
  let node: SchemaNode
  @Binding var value: JSONValue
  var focusedField: FocusState<String?>.Binding
  let isReadOnly: Bool
  let onValidate: () -> Void
  
  var body: some View {
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
          onValidate()
        }
      )
    )
    .toggleStyle(.switch)
    .controlSize(.small)
    .labelsHidden()
    .focusable()
    .focused(focusedField, equals: node.id)
    .disabled(isReadOnly)
  }
}