// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct JSONValueView: View {
  let jsonValue: JSONValue
  @State private var selectedTab: Tab = .json
  @State private var showCopiedMessage = false
  @State private var searchText = ""
  @State private var debouncedSearchText = ""
  @State private var searchDebounceTask: Task<Void, Never>?

  private var isSearchActive: Bool {
    return !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  enum Tab: String, CaseIterable {
    case json = "JSON"
    case raw = "Raw"
  }

  var body: some View {
    VStack(spacing: 0) {
      // Toolbar with tabs, search, and copy button
      JSONViewerToolbar(
        selectedTab: $selectedTab,
        searchText: $searchText,
        showCopiedMessage: $showCopiedMessage,
        jsonValue: jsonValue
      )

      // Content
      switch selectedTab {
      case .json:
        JSONOutlineView(
          jsonValue: jsonValue, searchText: debouncedSearchText, isSearchActive: isSearchActive
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .raw:
        ZStack {
          JSONRawView(
            jsonValue: jsonValue, searchText: debouncedSearchText, isSearchActive: isSearchActive
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          // Fade-out gradient overlay
          VStack(spacing: 0) {
            LinearGradient(
              gradient: Gradient(colors: [
                Color(NSColor.controlBackgroundColor),
                Color(NSColor.controlBackgroundColor).opacity(0.7),
                Color(NSColor.controlBackgroundColor).opacity(0.3),
                Color(NSColor.controlBackgroundColor).opacity(0.0),
              ]),
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(height: 12)

            Spacer()
          }
          .allowsHitTesting(false)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: searchText) { _, newValue in
      // Cancel any existing debounce task
      searchDebounceTask?.cancel()

      // Create new debounce task
      searchDebounceTask = Task {
        // Wait for 250ms
        try? await Task.sleep(nanoseconds: 250_000_000)

        // Check if task wasn't cancelled
        if !Task.isCancelled {
          await MainActor.run {
            debouncedSearchText = newValue
          }
        }
      }
    }
    .onDisappear {
      // Clean up debounce task when view disappears
      searchDebounceTask?.cancel()
    }
  }
}

#Preview {
  JSONValueView(
    jsonValue: .object([
      "name": .string("John Doe"),
      "age": .integer(30),
      "isActive": .boolean(true),
      "balance": .number(1234.56),
      "address": .object([
        "street": .string("123 Main St"),
        "city": .string("New York"),
        "coordinates": .array([.number(40.7128), .number(-74.0060)]),
      ]),
      "tags": .array([.string("user"), .string("premium")]),
      "metadata": .null,
    ])
  )
  .frame(width: 400, height: 600)
}
