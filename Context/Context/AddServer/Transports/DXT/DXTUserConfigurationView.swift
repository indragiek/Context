// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI
import UniformTypeIdentifiers

struct DXTUserConfigurationView: View {
  let manifest: DXTManifest
  @Binding var userConfig: DXTUserConfigurationValues
  let icon: NSImage?
  @Environment(\.dismiss) private var dismiss

  @State private var formValues: [String: FormValue] = [:]
  @State private var showingInfoFor: String?
  @State private var popoverButtonFrame: CGRect = .zero

  struct FormValue {
    var stringValue: String = ""
    var numberValue: Double = 0
    var boolValue: Bool = false
    var stringArrayValue: [String] = []
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(spacing: 12) {
        HStack(spacing: 12) {
          // Extension icon
          if let icon = icon {
            Image(nsImage: icon)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 32, height: 32)
              .cornerRadius(6)
          } else {
            Image(systemName: "puzzlepiece.extension.fill")
              .font(.system(size: 20))
              .foregroundColor(.accentColor)
              .frame(width: 32, height: 32)
              .background(
                RoundedRectangle(cornerRadius: 6)
                  .fill(Color.accentColor.opacity(0.1))
              )
          }

          VStack(alignment: .leading, spacing: 2) {
            Text(manifest.displayName ?? manifest.name)
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(.primary)

            Text("Version \(manifest.version)")
              .font(.system(size: 11))
              .foregroundColor(.secondary)
          }

          Spacer()
        }

        Text(manifest.description)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

      Divider()

      // Configuration Form
      ScrollView {
        VStack(spacing: 0) {
          if let userConfigItems = manifest.userConfig {
            ForEach(userConfigItems.sorted(by: { $0.key < $1.key }), id: \.key) { key, configItem in
              configurationRow(for: key, configItem: configItem)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

              if key != userConfigItems.sorted(by: { $0.key < $1.key }).last?.key {
                Divider()
                  .padding(.horizontal, 20)
              }
            }
          }
        }
        .padding(.vertical, 8)
      }

      Divider()

      // Bottom buttons
      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Cancel")
        .accessibilityHint("Close without saving configuration")

        Spacer()

        Button("Save") {
          saveConfiguration()
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(!isValid)
        .accessibilityLabel("Save configuration")
        .accessibilityHint(
          isValid ? "Save the extension configuration" : "Complete all required fields to enable")
      }
      .padding(20)
    }
    .frame(width: 600)
    .frame(minHeight: 400, maxHeight: 700)
    .onAppear {
      loadInitialValues()
    }
  }

  @ViewBuilder
  private func configurationRow(for key: String, configItem: DXTManifest.UserConfigItem)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      // Label row
      HStack(alignment: .center) {
        Text(configItem.title ?? key)
          .font(.system(size: 13, weight: .medium))

        if configItem.required == true {
          Text("Required")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.red)
            .cornerRadius(3)
        }

        Spacer()

        Button(action: {
          if showingInfoFor == key {
            showingInfoFor = nil
          } else {
            showingInfoFor = key
          }
        }) {
          Image(systemName: "info.circle")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Show more information")
        .popover(isPresented: Binding(
          get: { showingInfoFor == key },
          set: { isPresented in
            if !isPresented {
              showingInfoFor = nil
            }
          }
        )) {
          ConfigurationInfoPopover(
            key: key,
            configItem: configItem
          )
        }
      }

      // Control
      Group {
        switch configItem.type {
        case "string":
          if configItem.sensitive == true {
            SecureField(
              placeholderForConfig(configItem),
              text: binding(for: key).stringValue
            )
            .textFieldStyle(.roundedBorder)
          } else {
            TextField(
              placeholderForConfig(configItem),
              text: binding(for: key).stringValue
            )
            .textFieldStyle(.roundedBorder)
          }

        case "number":
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              TextField(
                placeholderForConfig(configItem),
                value: binding(for: key).numberValue,
                format: .number
              )
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 150)

              if let min = configItem.min, let max = configItem.max {
                Text("(\(Int(min))–\(Int(max)))")
                  .font(.system(size: 11))
                  .foregroundColor(.secondary)
              }

              Spacer()
            }

            // Validation error
            if let formValue = formValues[key] {
              if let min = configItem.min, formValue.numberValue < min {
                HStack(spacing: 4) {
                  Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                  Text("Value must be at least \(Int(min))")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                }
              } else if let max = configItem.max, formValue.numberValue > max {
                HStack(spacing: 4) {
                  Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                  Text("Value must be at most \(Int(max))")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                }
              }
            }
          }

        case "boolean":
          HStack(spacing: 8) {
            Toggle("", isOn: binding(for: key).boolValue)
              .toggleStyle(.switch)
              .labelsHidden()

            if let description = configItem.description {
              Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }

            Spacer()
          }

        case "directory", "file":
          if configItem.multiple == true {
            MultiplePathSelector(
              paths: binding(for: key).stringArrayValue,
              type: configItem.type == "directory" ? .folder : .item,
              sensitive: configItem.sensitive == true
            )
          } else {
            SinglePathSelector(
              path: binding(for: key).stringValue,
              type: configItem.type == "directory" ? .folder : .item,
              sensitive: configItem.sensitive == true
            )
          }

        default:
          Text("Unsupported type: \(configItem.type)")
            .font(.system(size: 12))
            .foregroundColor(.red)
        }
      }
    }
  }

  private func binding(for key: String) -> Binding<FormValue> {
    Binding(
      get: {
        formValues[key] ?? FormValue()
      },
      set: { newValue in
        formValues[key] = newValue
      }
    )
  }

  private func placeholderForConfig(_ configItem: DXTManifest.UserConfigItem) -> String {
    if let defaultValue = configItem.defaultValue {
      switch defaultValue {
      case .string(let str):
        return performSubstitutions(str)
      case .number(let num):
        return String(num)
      case .boolean(let bool):
        return String(bool)
      default:
        return ""
      }
    }
    return ""
  }

  private func performSubstitutions(_ value: String) -> String {
    var result = value

    // Get environment paths
    let fm = FileManager.default

    if let home = fm.homeDirectoryForCurrentUser.path as String? {
      result = result.replacingOccurrences(of: "${HOME}", with: home)
    }

    if let desktop = try? fm.url(
      for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false
    ).path {
      result = result.replacingOccurrences(of: "${DESKTOP}", with: desktop)
    }

    if let documents = try? fm.url(
      for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
    ).path {
      result = result.replacingOccurrences(of: "${DOCUMENTS}", with: documents)
    }

    return result
  }

  private func loadInitialValues() {
    guard let userConfigItems = manifest.userConfig else { return }

    // Load existing values from userConfig
    for (key, configValue) in userConfig.values {
      var formValue = FormValue()

      switch configValue.value {
      case .string(let str):
        formValue.stringValue = str
      case .number(let num):
        formValue.numberValue = num
      case .boolean(let bool):
        formValue.boolValue = bool
      case .stringArray(let arr):
        formValue.stringArrayValue = arr
      case .keychainReference:
        // Should not happen in UI - these should be resolved before showing
        break
      }

      formValues[key] = formValue
    }

    // Set defaults for missing values
    for (key, configItem) in userConfigItems {
      if formValues[key] == nil {
        var formValue = FormValue()

        if let defaultValue = configItem.defaultValue {
          switch defaultValue {
          case .string(let str):
            formValue.stringValue = performSubstitutions(str)
          case .number(let num):
            formValue.numberValue = num
          case .boolean(let bool):
            formValue.boolValue = bool
          case .array(let arr):
            formValue.stringArrayValue = arr.compactMap { val in
              if case .string(let str) = val {
                return performSubstitutions(str)
              }
              return nil
            }
          default:
            break
          }
        }

        formValues[key] = formValue
      }
    }
  }

  private func saveConfiguration() {
    guard let userConfigItems = manifest.userConfig else { return }

    var newValues: [String: DXTUserConfigurationValues.ConfigValue] = [:]

    for (key, configItem) in userConfigItems {
      guard let formValue = formValues[key] else { continue }

      let value: DXTUserConfigurationValues.ConfigValue.Value

      switch configItem.type {
      case "string", "directory", "file":
        if configItem.type == "directory" || configItem.type == "file" {
          if configItem.multiple == true && !formValue.stringArrayValue.isEmpty {
            value = .stringArray(formValue.stringArrayValue)
          } else if !formValue.stringValue.isEmpty {
            value = .string(formValue.stringValue)
          } else {
            continue  // Skip empty values
          }
        } else {
          if !formValue.stringValue.isEmpty {
            value = .string(formValue.stringValue)
          } else {
            continue
          }
        }

      case "number":
        value = .number(formValue.numberValue)

      case "boolean":
        value = .boolean(formValue.boolValue)

      default:
        continue
      }

      newValues[key] = DXTUserConfigurationValues.ConfigValue(
        value: value,
        isSensitive: configItem.sensitive == true,
        configType: configItem.type
      )
    }

    userConfig = DXTUserConfigurationValues(values: newValues)
  }

  private var isValid: Bool {
    guard let userConfigItems = manifest.userConfig else { return true }

    for (key, configItem) in userConfigItems {
      guard let formValue = formValues[key] else {
        // If no form value exists, check if it's required
        return configItem.required != true
      }

      switch configItem.type {
      case "string", "directory", "file":
        if configItem.required == true {
          if configItem.type == "directory" || configItem.type == "file" {
            if configItem.multiple == true {
              if formValue.stringArrayValue.isEmpty {
                return false
              }
            } else {
              if formValue.stringValue.isEmpty {
                return false
              }
            }
          } else {
            if formValue.stringValue.isEmpty {
              return false
            }
          }
        }

      case "number":
        // Always validate min/max for numbers, regardless of required status
        if let min = configItem.min, formValue.numberValue < min {
          return false
        }
        if let max = configItem.max, formValue.numberValue > max {
          return false
        }

      default:
        break
      }
    }

    return true
  }
}

struct SinglePathSelector: View {
  @Binding var path: String
  let type: UTType
  let sensitive: Bool
  @State private var showingFilePicker = false

  var body: some View {
    HStack(spacing: 8) {
      if sensitive {
        SecureField("", text: $path)
          .textFieldStyle(.roundedBorder)
      } else {
        TextField("", text: $path)
          .textFieldStyle(.roundedBorder)
          .placeholder(when: path.isEmpty) {
            Text("Select path...")
              .foregroundColor(.secondary)
          }
      }

      Button("Browse...") {
        showingFilePicker = true
      }
      .controlSize(.regular)
      .fileImporter(
        isPresented: $showingFilePicker,
        allowedContentTypes: [type],
        allowsMultipleSelection: false
      ) { result in
        if case .success(let urls) = result, let url = urls.first {
          path = url.path
        }
      }
    }
  }
}

struct MultiplePathSelector: View {
  @Binding var paths: [String]
  let type: UTType
  let sensitive: Bool
  @State private var showingFilePicker = false
  @State private var selectedIndex: Int?

  var body: some View {
    VStack(spacing: 0) {
      if paths.isEmpty {
        VStack(spacing: 4) {
          Image(systemName: type == .folder ? "folder.badge.plus" : "doc.badge.plus")
            .font(.system(size: 28))
            .foregroundColor(.secondary.opacity(0.5))
          Text("No \(type == .folder ? "folders" : "files") selected")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 100)
        .background(Color(NSColor.controlBackgroundColor))
      } else {
        ScrollView {
          VStack(spacing: 2) {
            ForEach(paths.indices, id: \.self) { index in
              HStack(spacing: 8) {
                Image(systemName: type == .folder ? "folder" : "doc")
                  .font(.system(size: 12))
                  .foregroundColor(.secondary)

                if sensitive {
                  Text("••••••")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                } else {
                  Text(paths[index])
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                }

                Spacer()
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(
                RoundedRectangle(cornerRadius: 4)
                  .fill(selectedIndex == index ? Color.accentColor.opacity(0.3) : Color.clear)
              )
              .contentShape(Rectangle())
              .onTapGesture {
                selectedIndex = index
              }
            }
          }
          .padding(4)
        }
        .frame(height: 100)
        .background(Color(NSColor.controlBackgroundColor))
      }

      HStack(spacing: 0) {
        Button(action: {
          showingFilePicker = true
        }) {
          Image(systemName: "plus")
            .font(.system(size: 10, weight: .medium))
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)

        Button(action: {
          if let index = selectedIndex, paths.indices.contains(index) {
            paths.remove(at: index)
            selectedIndex = nil
          }
        }) {
          Image(systemName: "minus")
            .font(.system(size: 10, weight: .medium))
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .disabled(selectedIndex == nil)

        Spacer()
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(Color(NSColor.windowBackgroundColor))
    }
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
    )
    .fileImporter(
      isPresented: $showingFilePicker,
      allowedContentTypes: [type],
      allowsMultipleSelection: true
    ) { result in
      if case .success(let urls) = result {
        paths.append(contentsOf: urls.map { $0.path })
      }
    }
  }
}

struct ConfigurationInfoPopover: View {
  let key: String
  let configItem: DXTManifest.UserConfigItem

  var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(spacing: 8) {
        Text(configItem.title ?? key)
          .font(.headline)
          .fontWeight(.semibold)

        if let description = configItem.description {
          Text(description)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.top, 16)
      .padding(.horizontal, 16)
      .padding(.bottom, 12)

      Divider()

      // Properties
      VStack(alignment: .leading, spacing: 10) {
        ConfigPropertyRow(label: "Type", value: typeDisplayName(configItem.type))

        if configItem.required == true {
          ConfigPropertyRow(label: "Required", value: "Yes", valueColor: .orange)
        }

        if configItem.sensitive == true {
          ConfigPropertyRow(label: "Security", value: "Stored securely in Keychain")
        }

        if configItem.multiple == true {
          ConfigPropertyRow(label: "Selection", value: "Multiple values allowed")
        }

        if let min = configItem.min, let max = configItem.max {
          ConfigPropertyRow(label: "Range", value: "\(Int(min)) – \(Int(max))")
        } else if let min = configItem.min {
          ConfigPropertyRow(label: "Minimum", value: String(format: "%.0f", min))
        } else if let max = configItem.max {
          ConfigPropertyRow(label: "Maximum", value: String(format: "%.0f", max))
        }

        if let defaultValue = configItem.defaultValue {
          ConfigPropertyRow(label: "Default", value: defaultValueDescription(defaultValue))
        }
      }
      .padding(16)
    }
    .frame(width: 320)
    .background(Color(NSColor.controlBackgroundColor))
  }

  private func typeDisplayName(_ type: String) -> String {
    switch type {
    case "string": return "Text"
    case "number": return "Number"
    case "boolean": return "Yes/No"
    case "directory": return "Folder"
    case "file": return "File"
    default: return type.capitalized
    }
  }

  private func defaultValueDescription(_ value: JSONValue) -> String {
    switch value {
    case .string(let str):
      return str
    case .number(let num):
      return String(format: "%.0f", num)
    case .boolean(let bool):
      return bool ? "Yes" : "No"
    case .array(let arr):
      let values = arr.compactMap { val -> String? in
        switch val {
        case .string(let str): return str
        case .number(let num): return String(format: "%.0f", num)
        case .boolean(let bool): return bool ? "Yes" : "No"
        default: return nil
        }
      }
      return values.joined(separator: ", ")
    default:
      return "None"
    }
  }
}

struct ConfigPropertyRow: View {
  let label: String
  let value: String
  var valueColor: Color = .primary

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Text(label + ":")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .frame(width: 80, alignment: .trailing)

      Text(value)
        .font(.system(size: 12))
        .foregroundColor(valueColor)
        .textSelection(.enabled)

      Spacer()
    }
  }
}

// Extension for placeholder support
extension View {
  func placeholder<Content: View>(
    when shouldShow: Bool,
    alignment: Alignment = .leading,
    @ViewBuilder placeholder: () -> Content
  ) -> some View {
    ZStack(alignment: alignment) {
      self
      if shouldShow {
        placeholder()
          .allowsHitTesting(false)
          .padding(.leading, 10)
      }
    }
  }
}

extension String: @retroactive Identifiable {
  public var id: String { self }
}
