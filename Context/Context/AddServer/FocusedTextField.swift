// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct FocusedTextField: View {
  let placeholder: String
  @Binding var text: String
  let shouldFocus: Bool
  let hasError: Bool
  let onFocusHandled: (() -> Void)?
  let onEditingChanged: ((Bool) -> Void)?
  @FocusState private var isFocused: Bool

  init(
    placeholder: String = "", text: Binding<String>, shouldFocus: Bool,
    hasError: Bool = false,
    onFocusHandled: (() -> Void)? = nil,
    onEditingChanged: ((Bool) -> Void)? = nil
  ) {
    self.placeholder = placeholder
    self._text = text
    self.shouldFocus = shouldFocus
    self.hasError = hasError
    self.onFocusHandled = onFocusHandled
    self.onEditingChanged = onEditingChanged
  }

  var body: some View {
    TextField(
      placeholder, text: $text,
      onEditingChanged: { editing in
        onEditingChanged?(editing)
      }
    )
    .textFieldStyle(.plain)
    .focused($isFocused)
    .overlay(
      RoundedRectangle(cornerRadius: 3)
        .stroke(hasError ? Color.red : Color.clear, lineWidth: 1)
    )
    .onAppear {
      if shouldFocus {
        // Use a small delay to ensure the view is fully rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
          isFocused = true
          onFocusHandled?()
        }
      }
    }
  }
}
