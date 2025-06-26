// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct JSONContentView: View {
  let contentLines: [String]
  let searchText: String
  let isSearchActive: Bool
  @Environment(\.colorScheme) private var colorScheme
  @State private var cachedSyntaxAttributedString: AttributedString?
  @State private var cachedContent: String = ""
  @State private var cachedColorScheme: ColorScheme?
  @State private var cachedSearchHighlightedString: AttributedString?
  @State private var cachedSearchText: String = ""

  private var joinedContent: String {
    contentLines.joined(separator: "\n")
  }

  var body: some View {
    Text(displayText)
      .font(.system(.body, design: .monospaced))
      .lineSpacing(5)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
      .padding(.top, 4)
      .background(Color(NSColor.textBackgroundColor))
      .onAppear {
        updateCacheIfNeeded()
        updateSearchCacheIfNeeded()
      }
      .onChange(of: joinedContent) { _, _ in
        updateCacheIfNeeded()
        updateSearchCacheIfNeeded()
      }
      .onChange(of: colorScheme) { _, _ in
        updateCacheIfNeeded()
        updateSearchCacheIfNeeded()
      }
      .onChange(of: searchText) { _, _ in
        updateSearchCacheIfNeeded()
      }
      .onChange(of: isSearchActive) { _, _ in
        updateSearchCacheIfNeeded()
      }
  }

  private var displayText: AttributedString {
    // This computed property should only READ from cached values, never modify them
    if let cached = cachedSearchHighlightedString {
      return cached
    } else if let cached = cachedSyntaxAttributedString {
      return cached
    } else {
      // Fallback plain text
      return AttributedString(joinedContent)
    }
  }

  private func updateCacheIfNeeded() {
    let currentContent = joinedContent
    let currentScheme = colorScheme

    if cachedSyntaxAttributedString == nil || cachedContent != currentContent
      || cachedColorScheme != currentScheme
    {
      // For very large JSON (> 10000 characters), defer syntax highlighting
      if currentContent.count > 10000 {
        // Show plain text immediately
        cachedSyntaxAttributedString = AttributedString(currentContent)
        cachedContent = currentContent
        cachedColorScheme = currentScheme

        // Schedule syntax highlighting for next run loop
        Task { @MainActor in
          let syntaxColorScheme =
            currentScheme == .dark
            ? JSONSyntaxHighlighter.darkScheme : JSONSyntaxHighlighter.lightScheme

          let highlighted = JSONSyntaxHighlighter.highlightToAttributedString(
            currentContent, colorScheme: syntaxColorScheme)

          // Only update if content hasn't changed
          if self.cachedContent == currentContent && self.cachedColorScheme == currentScheme {
            self.cachedSyntaxAttributedString = highlighted
            self.cachedSearchHighlightedString = nil
            self.cachedSearchText = ""
          }
        }
      } else {
        // For smaller JSON, highlight synchronously
        let syntaxColorScheme =
          currentScheme == .dark
          ? JSONSyntaxHighlighter.darkScheme : JSONSyntaxHighlighter.lightScheme

        cachedSyntaxAttributedString = JSONSyntaxHighlighter.highlightToAttributedString(
          currentContent, colorScheme: syntaxColorScheme)
        cachedContent = currentContent
        cachedColorScheme = currentScheme

        // Invalidate search cache when syntax cache changes
        cachedSearchHighlightedString = nil
        cachedSearchText = ""
      }
    }
  }

  private func updateSearchCacheIfNeeded() {
    let currentSearchText = isSearchActive ? searchText : ""

    // Always update if we have syntax highlighting available
    if let syntaxAttributedString = cachedSyntaxAttributedString {
      if currentSearchText.isEmpty {
        // No search active, use syntax highlighting directly
        cachedSearchHighlightedString = syntaxAttributedString
      } else {
        // Apply search highlighting
        cachedSearchHighlightedString = JSONSyntaxHighlighter.applySearchHighlighting(
          to: syntaxAttributedString,
          searchText: currentSearchText
        )
      }
      cachedSearchText = currentSearchText
    } else {
      // No syntax highlighting yet, clear search cache
      cachedSearchHighlightedString = nil
      cachedSearchText = ""
    }
  }
}
