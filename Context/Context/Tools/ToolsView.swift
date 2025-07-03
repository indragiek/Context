// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI

struct ToolsView: View {
  let store: StoreOf<ToolsFeature>
  @State private var selection: String?

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Group {
        if viewStore.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewStore.error {
          ContentUnavailableView {
            Label("Failed to Load Tools", systemImage: "exclamationmark.triangle")
          } description: {
            Text(error.localizedDescription)
          } actions: {
            if error.isLikelyConnectionError {
              Button("Reconnect") {
                viewStore.send(.reconnect)
              }
            }
          }
        } else if viewStore.tools.isEmpty {
          ContentUnavailableView(
            "No Tools",
            systemImage: "wrench.and.screwdriver",
            description: Text("No tools available")
          )
        } else if viewStore.filteredTools.isEmpty {
          ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("No tools match '\(viewStore.searchQuery)'")
          )
        } else {
          ScrollViewReader { proxy in
            List(
              viewStore.filteredTools,
              selection: $selection
            ) { tool in
              ToolRow(
                tool: tool,
                isSelected: viewStore.selectedToolName == tool.name
              )
              .id(tool.name)
              .contextMenu {
                Button("Copy Name") {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(tool.name, forType: .string)
                }
              }
            }
            .onChange(of: viewStore.searchQuery) { _, _ in
              // Reset scroll position to top for any search query change
              if let firstTool = viewStore.filteredTools.first {
                proxy.scrollTo(firstTool.name, anchor: .top)
              }
            }
          }
        }
      }
      .searchable(
        text: viewStore.binding(
          get: \.searchQuery,
          send: ToolsFeature.Action.searchQueryChanged
        ),
        prompt: "Search tools..."
      )
      .onAppear {
        selection = viewStore.selectedToolName
        viewStore.send(.onAppear)
      }
      .onChange(of: selection) { _, newValue in
        Task {
          viewStore.send(.toolSelected(newValue))
        }
      }
      .onChange(of: viewStore.selectedToolName) { _, newValue in
        selection = newValue
      }
    }
  }
}

struct ToolRow: View {
  let tool: Tool
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Name and description
      VStack(alignment: .leading, spacing: 3) {
        Text(tool.name)
          .font(.system(.body, weight: .medium))

        if let description = tool.description {
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
    // Extract required and optional parameters from inputSchema
    let properties = tool.inputSchema.properties ?? [:]
    let requiredSet = Set(tool.inputSchema.required ?? [])

    if properties.isEmpty {
      return Text("(no arguments)")
        .font(.system(.caption, design: .monospaced))
    }

    // Separate and sort parameters: required first, then optional
    let requiredParams = requiredSet.sorted()
    let optionalParams = properties.keys.filter { !requiredSet.contains($0) }.sorted()
    let allParams = requiredParams + optionalParams

    if allParams.count <= 3 {
      // Show all parameters if 3 or fewer
      return Text(allParams.joined(separator: ", "))
        .font(.system(.caption, design: .monospaced))
    } else {
      // Show first 3 parameters and count of remaining
      let firstThree = allParams.prefix(3).joined(separator: ", ")
      let remaining = allParams.count - 3

      return Text(firstThree)
        .font(.system(.caption, design: .monospaced))
        + Text(", and \(remaining) more")
        .font(.caption)
    }
  }
}
