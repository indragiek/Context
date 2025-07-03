// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct SearchField: View {
  @Binding var text: String
  var prompt: String = "Search"
  @FocusState private var isFocused: Bool
  
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
      
      TextField(prompt, text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 12))
        .focused($isFocused)
      
      // Always reserve space for the X button to prevent layout jumping
      ZStack {
        if !text.isEmpty {
          Button(action: {
            text = ""
          }) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.secondary)
              .opacity(0.7)
          }
          .buttonStyle(.plain)
          .transition(.scale.combined(with: .opacity))
        }
      }
      .frame(width: 16, height: 16)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color(NSColor.textBackgroundColor))
        .stroke(
          isFocused ? Color.accentColor : Color(NSColor.separatorColor),
          lineWidth: isFocused ? 2 : 0.5)
    )
  }
}