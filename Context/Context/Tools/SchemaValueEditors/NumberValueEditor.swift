// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct NumberValueEditor: View {
  let node: SchemaNode
  @Binding var value: JSONValue
  var focusedField: FocusState<String?>.Binding
  let isReadOnly: Bool
  let onValidate: () -> Void

  @Environment(\.toolSubmitAction) var toolSubmitAction
  @State private var textValue: String = ""
  @State private var isEditing: Bool = false

  private var numberValue: Double {
    if case .number(let num) = value { return num }
    return 0.0
  }

  private var formattedNumber: String {
    String(format: "%.10g", numberValue)
  }

  private func syncTextValue() {
    if case .number(let num) = value {
      textValue = String(format: "%.10g", num)
    } else if value.isNull {
      textValue = ""
    } else {
      textValue = "0.0"
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      ZStack(alignment: .trailing) {
        TextField(
          "0.0",
          text: Binding(
            get: {
              if isEditing {
                return textValue
              }
              return value.isNull ? "" : formattedNumber
            },
            set: { newValue in
              textValue = newValue
              if newValue.isEmpty {
                value = node.isRequired ? .number(0.0) : .null
              } else if let num = Double(newValue) {
                value = .number(num)
              } else if !newValue.isEmpty && value.isNull {
                value = .number(0.0)
              }
              onValidate()
            }
          ),
          onEditingChanged: { editing in
            isEditing = editing
            if !editing {
              syncTextValue()
            }
          }
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
            textValue = ""
            isEditing = false
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
          get: { numberValue },
          set: { newValue in
            value = .number(newValue)
            textValue = String(format: "%.10g", newValue)
            onValidate()
          }
        ),
        step: SchemaValueHelpers.extractStep(from: node.schema, defaultStep: 0.1)
      )
      .labelsHidden()
      .disabled(isReadOnly)
    }
    .onAppear {
      syncTextValue()
    }
    .onChange(of: value) { _, _ in
      if !isEditing {
        syncTextValue()
      }
    }
  }
}
