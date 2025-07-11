// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct PromptArgumentsView: View {
  let arguments: [PromptArgument]?
  @Binding var argumentValues: [String: String]
  @FocusState.Binding var focusedArgument: String?
  let allRequiredArgumentsFilled: Bool
  let isLoadingMessages: Bool
  let onSubmit: () -> Void
  let onArgumentChange: () -> Void
  
  var body: some View {
    if let arguments = arguments, !arguments.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("Arguments")
          .font(.headline)
        
        VStack(alignment: .leading, spacing: 8) {
          ForEach(arguments, id: \.name) { argument in
            ArgumentRow(
              argument: argument,
              value: Binding(
                get: { argumentValues[argument.name] ?? "" },
                set: { newValue in
                  argumentValues[argument.name] = newValue
                  onArgumentChange()
                }
              ),
              focusedArgument: $focusedArgument,
              allRequiredArgumentsFilled: allRequiredArgumentsFilled,
              isLoadingMessages: isLoadingMessages,
              onSubmit: onSubmit
            )
          }
        }
      }
    } else {
      Text("This prompt has no arguments")
        .font(.callout)
        .foregroundColor(.secondary)
    }
  }
}

private struct ArgumentRow: View {
  let argument: PromptArgument
  @Binding var value: String
  @FocusState.Binding var focusedArgument: String?
  let allRequiredArgumentsFilled: Bool
  let isLoadingMessages: Bool
  let onSubmit: () -> Void
  
  private var isRequired: Bool {
    argument.required == true
  }
  
  private var isFilledRequired: Bool {
    isRequired && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  
  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "curlybraces")
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(width: 16)
        
        Text(argument.name)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(.secondary)
          .help(argument.description ?? "")
      }
      .frame(width: 120, alignment: .leading)
      
      TextField(
        isRequired ? "Required" : "Optional",
        text: $value
      )
      .textFieldStyle(.roundedBorder)
      .font(.system(.caption, design: .monospaced))
      .focused($focusedArgument, equals: argument.name)
      .foregroundColor(
        isFilledRequired ? .primary : (isRequired ? .red : .primary)
      )
      .onSubmit {
        if allRequiredArgumentsFilled && !isLoadingMessages {
          onSubmit()
        }
      }
    }
  }
}