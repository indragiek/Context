// Copyright © 2025 Indragie Karunaratne. All rights reserved.

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
  let server: MCPServer
  let promptName: String
  
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
              onSubmit: onSubmit,
              server: server,
              promptName: promptName
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
  let server: MCPServer
  let promptName: String
  
  @State private var completions: [String] = []
  @State private var isLoadingCompletions = false
  @State private var hasSelectedCompletion = false
  
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
      .textInputSuggestions {
        if !hasSelectedCompletion {
          ForEach(completions, id: \.self) { completion in
            Text(completion)
              .foregroundColor(.primary)
              .textInputCompletion(completion)
          }
        }
      }
      .onChange(of: value) { oldValue, newValue in
        // Only fetch completions if the user actually typed (not from selection)
        if focusedArgument == argument.name && oldValue != newValue {
          hasSelectedCompletion = false
          fetchCompletions(for: newValue)
        }
        // If the new value matches a completion, mark as selected
        if completions.contains(newValue) {
          hasSelectedCompletion = true
        }
      }
      .onChange(of: focusedArgument) { _, focused in
        if focused == argument.name {
          // Fetch completions when field is focused, even with empty value
          hasSelectedCompletion = false
          fetchCompletions(for: value)
        } else if focused != argument.name {
          completions = []
          hasSelectedCompletion = false
        }
      }
    }
  }
  
  private func fetchCompletions(for currentValue: String) {
    @Dependency(\.mcpClientManager) var mcpClientManager
    
    Task {
      isLoadingCompletions = true
      defer { isLoadingCompletions = false }
      
      do {
        guard let client = await mcpClientManager.existingClient(for: server) else {
          return
        }
        
        // Check if server supports completions
        guard await client.serverCapabilities?.completions != nil else {
          return
        }
        
        let reference = Reference.prompt(name: promptName)
        let (values, _, _) = try await client.complete(
          ref: reference,
          argumentName: argument.name,
          argumentValue: currentValue
        )
        
        await MainActor.run {
          completions = values
        }
      } catch {
        // Silently fail - completions are optional
        await MainActor.run {
          completions = []
        }
      }
    }
  }
}