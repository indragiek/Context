// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages
import ContextCore
import AppKit

enum JSONEditorError: LocalizedError {
  case emptyInput
  case invalidStructure(String)
  
  var errorDescription: String? {
    switch self {
    case .emptyInput:
      return "Empty input is not valid JSON"
    case .invalidStructure(let message):
      return message
    }
  }
}

struct JSONEditor: View {
  @Binding var text: String
  let isEditable: Bool
  let onValidate: ((Result<JSONValue, any Error>) -> Void)?
  
  @State private var state = SourceEditorState()
  @State private var validationTask: Task<Void, Never>?
  @Environment(\.colorScheme) var colorScheme
  
  private var configuration: SourceEditorConfiguration {
    let theme = makeTheme(for: colorScheme)
    let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    return SourceEditorConfiguration(
      appearance: .init(
        theme: theme,
        useThemeBackground: true,
        font: font,
        lineHeightMultiple: 1.45,
        letterSpacing: 1.0,
        wrapLines: true,
        tabWidth: 2
      ),
      behavior: .init(
        isEditable: isEditable,
        isSelectable: true,
        indentOption: .spaces(count: 2)
      ),
      layout: .init(),
      peripherals: .init(
        showGutter: true,
        showMinimap: false
      )
    )
  }
  
  private func makeTheme(for colorScheme: ColorScheme) -> EditorTheme {
    if colorScheme == .dark {
      // Match JSONSyntaxHighlighter dark scheme colors
      return EditorTheme(
        text: .init(color: .init(hex: 0xCCCCCC)),
        insertionPoint: .init(hex: 0xFFFFFF),
        invisibles: .init(color: .init(hex: 0x424242)),
        background: .init(hex: 0x1F1F1F),
        lineHighlight: .init(hex: 0x2F3239),
        selection: .init(hex: 0x264F78),
        keywords: .init(color: .init(hex: 0xE3ABFF)), // boolean/null color
        commands: .init(color: .init(hex: 0x66D9D9)), // key color
        types: .init(color: .init(hex: 0x66D9D9)), // key color
        attributes: .init(color: .init(hex: 0x66D9D9)), // key color
        variables: .init(color: .init(hex: 0x66D9D9)), // key color
        values: .init(color: .init(hex: 0xE3ABFF)), // boolean/null color
        numbers: .init(color: .init(hex: 0xABD9FF)), // number color
        strings: .init(color: .init(hex: 0xFF5454)), // string color
        characters: .init(color: .init(hex: 0xFF5454)), // string color
        comments: .init(color: .init(hex: 0x6A9955))
      )
    } else {
      // Match JSONSyntaxHighlighter light scheme colors
      return EditorTheme(
        text: .init(color: .init(hex: 0x3B3B3B)),
        insertionPoint: .init(hex: 0x000000),
        invisibles: .init(color: .init(hex: 0xD4D4D4)),
        background: .init(hex: 0xFBFBFB),
        lineHighlight: .init(hex: 0xF5F5F5),
        selection: .init(hex: 0xADD6FF),
        keywords: .init(color: .init(hex: 0xA31CAE)), // boolean/null color
        commands: .init(color: .init(hex: 0x007373)), // key color
        types: .init(color: .init(hex: 0x007373)), // key color
        attributes: .init(color: .init(hex: 0x007373)), // key color
        variables: .init(color: .init(hex: 0x007373)), // key color
        values: .init(color: .init(hex: 0xA31CAE)), // boolean/null color
        numbers: .init(color: .init(hex: 0x1C00CF)), // number color
        strings: .init(color: .init(hex: 0xC41A16)), // string color
        characters: .init(color: .init(hex: 0xC41A16)), // string color
        comments: .init(color: .init(hex: 0x008000))
      )
    }
  }
  
  var body: some View {
    CodeEditSourceEditor.SourceEditor(
      $text,
      language: .json,
      configuration: configuration,
      state: $state
    )
    .zIndex(-1)
    .onChange(of: text) { _, newText in
      if isEditable {
        // Cancel previous validation task
        validationTask?.cancel()
        
        // Create new task with 0.3 second delay
        validationTask = Task {
          do {
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            if !Task.isCancelled {
              validateJSON(newText)
            }
          } catch {
            // Task was cancelled
          }
        }
      }
    }
    .onDisappear {
      validationTask?.cancel()
    }
  }
  
  private func validateJSON(_ newText: String) {
    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard !trimmed.isEmpty else {
      // Empty text is invalid JSON
      onValidate?(.failure(JSONEditorError.emptyInput))
      return
    }
    
    do {
      let decoded = try JSONValue(decoding: newText)
      onValidate?(.success(decoded))
    } catch {
      // Invalid JSON - pass the error to the parent
      onValidate?(.failure(error))
    }
  }
}

// Preview provider for SwiftUI previews
struct JSONEditor_Previews: PreviewProvider {
  @State static var previewText = """
    {
      "name": "John Doe",
      "age": 30,
      "active": true
    }
    """
  
  static var previews: some View {
    JSONEditor(
      text: $previewText,
      isEditable: true,
      onValidate: { result in
        print("Validation result: \(result)")
      }
    )
    .frame(width: 600, height: 400)
  }
}
