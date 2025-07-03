// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI

struct PromptsView: View {
  let store: StoreOf<PromptsFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Group {
        if viewStore.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewStore.error {
          ContentUnavailableView {
            Label("Failed to Load Prompts", systemImage: "exclamationmark.triangle")
          } description: {
            Text(error.localizedDescription)
          } actions: {
            if error.isLikelyConnectionError {
              Button("Reconnect") {
                viewStore.send(.reconnect)
              }
            }
          }
        } else if viewStore.prompts.isEmpty {
          ContentUnavailableView(
            "No Prompts",
            systemImage: "text.bubble",
            description: Text("No prompts available")
          )
        } else if viewStore.filteredPrompts.isEmpty {
          ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("No prompts match '\(viewStore.searchQuery)'")
          )
        } else {
          ScrollViewReader { proxy in
            List(
              viewStore.filteredPrompts,
              selection: viewStore.binding(
                get: \.selectedPromptName,
                send: PromptsFeature.Action.promptSelected
              )
            ) { prompt in
              PromptRow(
                prompt: prompt,
                isSelected: viewStore.selectedPromptName == prompt.name
              )
              .id(prompt.name)
              .contextMenu {
                Button("Copy Name") {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(prompt.name, forType: .string)
                }
              }
            }
            .onChange(of: viewStore.searchQuery) { _, _ in
              // Reset scroll position to top for any search query change
              if let firstPrompt = viewStore.filteredPrompts.first {
                proxy.scrollTo(firstPrompt.name, anchor: .top)
              }
            }
          }
        }
      }
      .searchable(
        text: viewStore.binding(
          get: \.searchQuery,
          send: PromptsFeature.Action.searchQueryChanged
        ),
        prompt: "Search prompts..."
      )
      .onAppear {
        viewStore.send(.onAppear)
      }
    }
  }
}

struct PromptRow: View {
  let prompt: Prompt
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Name and description
      VStack(alignment: .leading, spacing: 3) {
        Text(prompt.name)
          .font(.system(.body, weight: .medium))

        if let description = prompt.description {
          Text(description)
            .font(.callout)
            .foregroundColor(.secondary)
            .lineLimit(2)
        }
      }

      // Parameters preview
      parametersPreviewText
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .padding(.vertical, 4)
  }

  private var parametersPreviewText: Text {
    guard let arguments = prompt.arguments, !arguments.isEmpty else {
      return Text("(no arguments)")
        .font(.system(.caption, design: .monospaced))
    }

    let argumentNames = arguments.map { $0.name }

    if argumentNames.count <= 3 {
      // Show all arguments if 3 or fewer
      return Text(argumentNames.joined(separator: ", "))
        .font(.system(.caption, design: .monospaced))
    } else {
      // Show first 3 arguments and count of remaining
      let firstThree = argumentNames.prefix(3).joined(separator: ", ")
      let remaining = argumentNames.count - 3

      return Text(firstThree)
        .font(.system(.caption, design: .monospaced))
        + Text(", and \(remaining) more")
        .font(.caption)
    }
  }
}
