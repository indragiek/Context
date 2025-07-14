// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct IntegerValueEditor: View {
  let node: SchemaNode
  @Binding var value: JSONValue
  var focusedField: FocusState<String?>.Binding
  let isReadOnly: Bool
  let onValidate: () -> Void
  
  @Environment(\.toolSubmitAction) var toolSubmitAction
  
  var body: some View {
    HStack(spacing: 8) {
      ZStack(alignment: .trailing) {
        TextField(
          "0",
          text: Binding(
            get: {
              if case .integer(let int) = value {
                return String(int)
              } else if value.isNull {
                return ""
              }
              return "0"
            },
            set: { newValue in
              if newValue.isEmpty {
                // For required fields, empty means 0; for optional fields, empty means null
                value = node.isRequired ? .integer(0) : .null
              } else if let int = Int64(newValue) {
                value = .integer(int)
              } else if !newValue.isEmpty {
                // If they're typing but it's not a valid integer yet, convert null to 0
                if value.isNull {
                  value = .integer(0)
                }
              }
              onValidate()
            }
          )
        )
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, design: .monospaced))
        .frame(width: 100)
        .focused(focusedField, equals: node.id)
        .disabled(isReadOnly)
        .onSubmit {
          toolSubmitAction?()
        }
        .submitLabel(.done)
        
        // Clear button inside the field - only show for optional fields
        if !node.isRequired && !value.isNull && !isReadOnly {
          Button(action: {
            value = .null
            onValidate()
          }) {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary.opacity(0.5))
              .font(.system(size: 14))
          }
          .buttonStyle(.plain)
          .help("Clear value")
          .padding(.trailing, 4)
        }
      }
      
      Stepper(
        "",
        value: Binding(
          get: {
            if case .integer(let int) = value {
              return Int(int)
            }
            return 0
          },
          set: { newValue in
            value = .integer(Int64(newValue))
            onValidate()
          }
        ),
        step: 1
      )
      .labelsHidden()
      .disabled(isReadOnly)
    }
  }
}