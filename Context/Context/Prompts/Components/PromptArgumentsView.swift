// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import SwiftUI

struct PromptArgumentsView: View {
  let arguments: [PromptArgument]?
  @Binding var argumentValues: [String: String]
  @FocusState.Binding var focusedArgument: String?
  let allRequiredArgumentsFilled: Bool
  let isLoadingMessages: Bool
  let onSubmit: () -> Void
  let onArgumentChange: () -> Void
  let promptName: String
  let store: StoreOf<PromptsFeature>

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
                  let oldValue = argumentValues[argument.name] ?? ""
                  argumentValues[argument.name] = newValue
                  onArgumentChange()
                  store.send(
                    .argumentValueChanged(
                      promptName: promptName,
                      argumentName: argument.name,
                      oldValue: oldValue,
                      newValue: newValue
                    ))
                }
              ),
              focusedArgument: $focusedArgument,
              allRequiredArgumentsFilled: allRequiredArgumentsFilled,
              isLoadingMessages: isLoadingMessages,
              onSubmit: onSubmit,
              promptName: promptName,
              store: store
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
  let promptName: String
  let store: StoreOf<PromptsFeature>

  private var isRequired: Bool {
    argument.required == true
  }

  private var isFilledRequired: Bool {
    isRequired && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    WithViewStore(store, observe: { $0.promptCompletions[promptName] }) { viewStore in
      let completionState = viewStore.state ?? PromptCompletionState()
      let completions = completionState.argumentCompletions[argument.name] ?? []
      let hasSelectedCompletion = completionState.hasSelectedCompletion[argument.name] ?? false

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
        .textInputSuggestions {
          if !hasSelectedCompletion {
            ForEach(completions, id: \.self) { completion in
              Text(completion)
                .foregroundColor(.primary)
                .textInputCompletion(completion)
            }
          }
        }
        .onChange(of: focusedArgument) { _, focused in
          store.send(
            .argumentFocusChanged(
              promptName: promptName,
              argumentName: focused == argument.name ? argument.name : nil,
              value: value
            ))
        }
      }
    }
  }
}
