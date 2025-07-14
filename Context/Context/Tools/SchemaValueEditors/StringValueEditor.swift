// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import ContextCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct StringValueEditor: View {
  let node: SchemaNode
  @Binding var value: JSONValue
  var focusedField: FocusState<String?>.Binding
  let isReadOnly: Bool
  let onValidate: () -> Void

  @Environment(\.toolSubmitAction) var toolSubmitAction
  @State private var showingFileImporter = false

  private var format: String? {
    if case .object(let obj) = node.schema,
      case .string(let format) = obj["format"]
    {
      return format
    }
    return nil
  }

  private var enumValues: [JSONValue]? {
    SchemaValueHelpers.extractEnum(from: node.schema)
  }

  var body: some View {
    if let enumValues = enumValues, !enumValues.isEmpty {
      enumPicker(enumValues: enumValues)
    } else if let format = format {
      switch format {
      case "color":
        colorPickerEditor
      case "uri", "url":
        uriPickerEditor
      case "date", "time", "date-time":
        datePickerEditor
      default:
        textFieldEditor
      }
    } else {
      textFieldEditor
    }
  }

  @ViewBuilder
  private func enumPicker(enumValues: [JSONValue]) -> some View {
    HStack {
      // For optional fields, include null as an option
      let effectiveEnumValues: [JSONValue] = node.isRequired ? enumValues : [.null] + enumValues

      Picker(
        "",
        selection: Binding(
          get: {
            // Find the index of the current value in the enum
            if let index = effectiveEnumValues.firstIndex(where: {
              JSONValueUtilities.jsonValuesEqual($0, value)
            }) {
              return index
            }
            // For optional fields, default to null (index 0)
            return node.isRequired ? 0 : 0
          },
          set: { newIndex in
            if newIndex < effectiveEnumValues.count {
              value = effectiveEnumValues[newIndex]
              onValidate()
            }
          }
        )
      ) {
        ForEach(0..<effectiveEnumValues.count, id: \.self) { index in
          if index == 0 && !node.isRequired && effectiveEnumValues[index].isNull {
            Text("").tag(index)  // Empty string for null option
          } else {
            Text(enumDisplayValue(effectiveEnumValues[index])).tag(index)
          }
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .focusable()
      .focused(focusedField, equals: node.id)
      .disabled(isReadOnly)
      .onKeyPress(.upArrow) {
        moveSelection(by: -1, in: effectiveEnumValues)
        return .handled
      }
      .onKeyPress(.downArrow) {
        moveSelection(by: 1, in: effectiveEnumValues)
        return .handled
      }
      .onAppear {
        // For optional fields, default to null if current value is not in enum
        if !node.isRequired
          && !effectiveEnumValues.contains(where: { JSONValueUtilities.jsonValuesEqual($0, value) })
        {
          value = .null
        } else if node.isRequired
          && !enumValues.contains(where: { JSONValueUtilities.jsonValuesEqual($0, value) })
        {
          // For required fields, default to first enum option
          if let firstEnum = enumValues.first {
            value = firstEnum
          }
        }
      }
    }
  }

  private func moveSelection(by offset: Int, in enumValues: [JSONValue]) {
    guard
      let currentIndex = enumValues.firstIndex(where: {
        JSONValueUtilities.jsonValuesEqual($0, value)
      })
    else { return }

    let newIndex = max(0, min(enumValues.count - 1, currentIndex + offset))
    if newIndex != currentIndex {
      value = enumValues[newIndex]
      // Delay validation slightly to ensure the value is properly set
      Task { @MainActor in
        self.onValidate()
      }
    }
  }

  private var colorPickerEditor: some View {
    HStack(spacing: 8) {
      ColorPicker(
        "",
        selection: Binding(
          get: {
            // Convert color string to Color
            if case .string(let colorStr) = value {
              return ColorConversionHelpers.colorFromString(colorStr) ?? Color.black
            }
            return Color.black
          },
          set: { newColor in
            // Convert Color to string
            value = .string(ColorConversionHelpers.colorToHexString(newColor))
            onValidate()
          }
        ),
        supportsOpacity: true
      )
      .labelsHidden()
      .disabled(isReadOnly)

      // Show the hex value
      textFieldWithClear(
        placeholder: "#000000",
        text: stringBinding(),
        width: 100
      )
    }
  }

  private var uriPickerEditor: some View {
    HStack(spacing: 8) {
      textFieldWithClear(
        placeholder: "Enter URI",
        text: stringBinding()
      )

      Button("Browse...") {
        showingFileImporter = true
      }
      .disabled(isReadOnly)
    }
    .fileImporter(
      isPresented: $showingFileImporter,
      allowedContentTypes: [.item],  // Allow any file type
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let url = urls.first {
          // Convert file URL to string
          value = .string(url.absoluteString)
          onValidate()
        }
      case .failure(let error):
        // Handle error if needed
        print("File picker error: \(error)")
      }
    }
  }

  private var datePickerEditor: some View {
    HStack(spacing: 8) {
      DatePicker(
        "",
        selection: Binding(
          get: {
            // Parse the string value to Date
            if case .string(let dateStr) = value {
              return DateConversionHelpers.parseDate(
                from: dateStr, format: format ?? "date-time") ?? Date()
            }
            return Date()
          },
          set: { newDate in
            // Convert Date to string
            value = .string(
              DateConversionHelpers.formatDate(newDate, format: format ?? "date-time"))
            onValidate()
          }
        ),
        displayedComponents: datePickerComponents
      )
      .labelsHidden()
      .datePickerStyle(.compact)
      .disabled(isReadOnly)

      // Show the formatted value
      textFieldWithClear(
        placeholder: datePlaceholder,
        text: stringBinding(),
        minWidth: dateMinWidth
      )
    }
  }

  private var datePickerComponents: DatePicker.Components {
    switch format {
    case "date":
      return [.date]
    case "time":
      return [.hourAndMinute]
    case "date-time":
      return [.date, .hourAndMinute]
    default:
      return [.date, .hourAndMinute]
    }
  }

  private var datePlaceholder: String {
    switch format {
    case "date":
      return "YYYY-MM-DD"
    case "time":
      return "HH:MM:SS"
    default:
      return "YYYY-MM-DDTHH:MM:SSZ"
    }
  }

  private var dateMinWidth: CGFloat {
    switch format {
    case "date":
      return 110
    case "time":
      return 100
    default:
      return 200
    }
  }

  private var textFieldEditor: some View {
    VStack(alignment: .leading, spacing: 2) {
      textFieldWithClear(
        placeholder: placeholderText,
        text: stringBinding()
      )

      // Show examples if available
      if let exampleText = getExampleText() {
        Text(exampleText)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  private var placeholderText: String {
    if let examples = getExamples(), !examples.isEmpty {
      if case .string(let example) = examples[0] {
        return example
      }
    }
    return "Enter text"
  }

  private func getExamples() -> [JSONValue]? {
    if case .object(let obj) = node.schema,
      case .array(let examples) = obj["examples"]
    {
      return examples
    }
    return nil
  }

  private func getExampleText() -> String? {
    guard let examples = getExamples(), !examples.isEmpty else { return nil }

    let exampleStrings = examples.prefix(3).compactMap { example -> String? in
      switch example {
      case .string(let str):
        return "\"\(str)\""
      case .number(let num):
        return String(num)
      case .integer(let int):
        return String(int)
      case .boolean(let bool):
        return String(bool)
      case .null:
        return "null"
      default:
        return nil
      }
    }

    if exampleStrings.isEmpty { return nil }

    let text =
      "Example\(exampleStrings.count > 1 ? "s" : ""): \(exampleStrings.joined(separator: ", "))"
    if examples.count > 3 {
      return text + "..."
    }
    return text
  }

  // Create a binding that preserves null values
  private func stringBinding() -> Binding<String> {
    Binding(
      get: {
        switch value {
        case .string(let str):
          return str
        case .null:
          return ""
        default:
          // For any other type, return empty string
          return ""
        }
      },
      set: { newValue in
        // For optional fields, as soon as user starts typing, convert null to empty string
        value = .string(newValue)
        onValidate()
      }
    )
  }

  // Common text field with clear button
  @ViewBuilder
  private func textFieldWithClear(
    placeholder: String,
    text: Binding<String>,
    width: CGFloat? = nil,
    minWidth: CGFloat? = nil
  ) -> some View {
    ZStack(alignment: .trailing) {
      TextField(
        placeholder,
        text: text
      )
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 12, design: .monospaced))
      .focused(focusedField, equals: node.id)
      .disabled(isReadOnly)
      .onSubmit {
        toolSubmitAction?()
      }
      .submitLabel(.done)
      .if(width != nil) { view in
        view.frame(width: width)
      }
      .if(minWidth != nil) { view in
        view.frame(minWidth: minWidth)
      }

      // Clear button inside the field - only show for optional fields
      if !node.isRequired && !value.isNull && !isReadOnly {
        Button(action: {
          value = .null
          onValidate()
        }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary.opacity(0.5))
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .help("Clear value")
        .padding(.trailing, 4)
      }
    }
  }

  private func enumDisplayValue(_ value: JSONValue) -> String {
    switch value {
    case .null:
      return "null"
    case .boolean(let b):
      return b ? "true" : "false"
    case .integer(let i):
      return String(i)
    case .number(let n):
      return String(n)
    case .string(let s):
      return s
    default:
      return JSONValueUtilities.jsonValueToString(value)
    }
  }
}
