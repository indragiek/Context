// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages
import ContextCore
import AppKit

struct JSONEditor: View {
  @Binding var text: String
  let isEditable: Bool
  let onValidate: ((Result<JSONValue, any Error>) -> Void)?
  
  @State private var state = SourceEditorState()
  @Environment(\.colorScheme) var colorScheme
  
  private var configuration: SourceEditorConfiguration {
    let theme = makeTheme(for: colorScheme)
    let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    
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
      // Dark theme colors similar to Xcode
      return EditorTheme(
        text: .init(color: .init(hex: 0xD6D6D6)),
        insertionPoint: .init(hex: 0xFFFFFF),
        invisibles: .init(color: .init(hex: 0x424242)),
        background: .init(hex: 0x1F1F24),
        lineHighlight: .init(hex: 0x2F3239),
        selection: .init(hex: 0x646F83),
        keywords: .init(color: .init(hex: 0xFC5FA3)),
        commands: .init(color: .init(hex: 0x67B7A4)),
        types: .init(color: .init(hex: 0x5DD8FF)),
        attributes: .init(color: .init(hex: 0xFC6A5D)),
        variables: .init(color: .init(hex: 0x41A1C0)),
        values: .init(color: .init(hex: 0xFC6A5D)),
        numbers: .init(color: .init(hex: 0xD0BF69)),
        strings: .init(color: .init(hex: 0xFC6A5D)),
        characters: .init(color: .init(hex: 0xD0BF69)),
        comments: .init(color: .init(hex: 0x6C7986))
      )
    } else {
      // Light theme colors similar to Xcode
      return EditorTheme(
        text: .init(color: .init(hex: 0x000000)),
        insertionPoint: .init(hex: 0x000000),
        invisibles: .init(color: .init(hex: 0xD4D4D4)),
        background: .init(hex: 0xFFFFFF),
        lineHighlight: .init(hex: 0xECF5FF),
        selection: .init(hex: 0xB3D7FF),
        keywords: .init(color: .init(hex: 0xAD3DA4)),
        commands: .init(color: .init(hex: 0x4B23A0)),
        types: .init(color: .init(hex: 0x0B4F79)),
        attributes: .init(color: .init(hex: 0x78492A)),
        variables: .init(color: .init(hex: 0x326D74)),
        values: .init(color: .init(hex: 0x78492A)),
        numbers: .init(color: .init(hex: 0x272AD8)),
        strings: .init(color: .init(hex: 0xD12F1B)),
        characters: .init(color: .init(hex: 0x272AD8)),
        comments: .init(color: .init(hex: 0x5D6C79))
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
    .onChange(of: text) { _, newText in
      if isEditable {
        validateJSON(newText)
      }
    }
  }
  
  private func validateJSON(_ newText: String) {
    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard !trimmed.isEmpty else {
      // Empty text is valid - empty object
      onValidate?(.success(.object([:])))
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