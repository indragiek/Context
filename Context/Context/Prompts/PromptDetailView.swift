// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AVKit
import ComposableArchitecture
import ContextCore
import MarkdownUI
import SwiftUI

struct PromptDetailView: View {
  let prompt: Prompt
  let server: MCPServer
  let store: StoreOf<PromptsFeature>

  // View-specific state only
  @FocusState private var focusedArgument: String?
  @State private var showingFullDescription = false

  var body: some View {
    WithViewStore(store, observe: { $0.promptState(for: prompt.name) }) { viewStore in
      let promptState = viewStore.state

      VSplitView {
        // Top pane - Header and arguments
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            PromptHeaderView(
              prompt: prompt,
              showingFullDescription: $showingFullDescription
            )

            Divider()

            PromptArgumentsView(
              arguments: prompt.arguments,
              argumentValues: Binding(
                get: { promptState.argumentValues },
                set: { newValues in
                  var updatedState = promptState
                  updatedState.argumentValues = newValues
                  store.send(.updatePromptState(promptName: prompt.name, promptState: updatedState))
                }
              ),
              focusedArgument: $focusedArgument,
              allRequiredArgumentsFilled: allRequiredArgumentsFilled(promptState: promptState),
              isLoadingMessages: promptState.loadingState == .loading,
              onSubmit: { store.send(.fetchPromptMessages(prompt: prompt)) },
              onArgumentChange: {
                // No-op - individual changes are handled by argumentValueChanged action
              },
              promptName: prompt.name,
              store: store
            )

            Spacer()
          }
          .padding(20)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .frame(minHeight: 200, idealHeight: max(200, calculateIdealHeight()))

        // Bottom pane - Messages
        PromptMessagesView(
          prompt: prompt,
          promptState: promptState,
          viewMode: Binding(
            get: { promptState.viewMode },
            set: { newMode in
              var updatedState = promptState
              updatedState.viewMode = newMode
              store.send(.updatePromptState(promptName: prompt.name, promptState: updatedState))
            }
          ),
          isLoading: promptState.loadingState == .loading,
          allRequiredArgumentsFilled: allRequiredArgumentsFilled(promptState: promptState),
          onFetchMessages: { store.send(.fetchPromptMessages(prompt: prompt)) },
          errorView: { error in
            AnyView(JSONRPCErrorView(error: error))
          },
          rawView: {
            AnyView(PromptRawDataView(promptState: promptState))
          }
        )
      }
      .sheet(isPresented: $showingFullDescription) {
        fullDescriptionSheet
      }
      .onAppear {
        store.send(.loadPromptState(promptName: prompt.name))
        store.send(.initializePromptArguments(prompt: prompt))

        // Auto-fetch if prompt has no arguments
        if (prompt.arguments == nil || prompt.arguments?.isEmpty == true)
          && !promptState.hasLoadedOnce
        {
          store.send(.fetchPromptMessages(prompt: prompt))
        }
      }
      .onDisappear {
        store.send(.cancelPromptMessagesFetch(promptName: prompt.name))
        // Clear completion state when view disappears
        store.send(.clearCompletionState(promptName: prompt.name))
      }
    }
  }

  // MARK: - Private Helpers

  private func allRequiredArgumentsFilled(promptState: PromptState) -> Bool {
    guard let arguments = prompt.arguments else { return true }

    return arguments.allSatisfy { argument in
      if argument.required == true {
        let value = promptState.argumentValues[argument.name] ?? ""
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      return true
    }
  }

  private func calculateIdealHeight() -> CGFloat {
    let baseHeight: CGFloat = 160
    let argumentHeight: CGFloat = 40
    let argumentsCount = min(prompt.arguments?.count ?? 0, 3)
    return baseHeight + (CGFloat(argumentsCount) * argumentHeight)
  }
}

// MARK: - Full Description Sheet

extension PromptDetailView {
  @ViewBuilder
  private var fullDescriptionSheet: some View {
    VStack(spacing: 20) {
      HStack {
        Text(prompt.name)
          .font(.title2)
          .fontWeight(.semibold)

        Spacer()

        Button("Done") {
          showingFullDescription = false
        }
        .keyboardShortcut(.defaultAction)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let description = prompt.description {
            Markdown(description)
              .markdownTextStyle {
                ForegroundColor(.primary)
              }
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let arguments = prompt.arguments, !arguments.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
              Text("Arguments")
                .font(.headline)

              ForEach(arguments, id: \.name) { argument in
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(argument.name)
                      .font(.subheadline)
                      .fontWeight(.medium)

                    if argument.required ?? false {
                      Text("Required")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                          RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.2))
                        )
                        .foregroundColor(.red)
                    }
                  }

                  if let desc = argument.description {
                    Markdown(desc)
                      .markdownTextStyle {
                        ForegroundColor(.secondary)
                      }
                      .font(.caption)
                      .textSelection(.enabled)
                  }
                }
                .padding(.vertical, 4)
              }
            }
          }
        }
        .padding(.vertical)
      }
    }
    .padding(20)
    .frame(width: 600, height: 400)
  }
}
