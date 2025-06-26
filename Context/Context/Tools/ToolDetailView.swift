// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import GRDB
import MarkdownUI
import SharingGRDB
import SwiftUI

struct ToolDetailView: View {
  let tool: Tool
  @Binding var toolState: ToolState
  let server: MCPServer
  let onStateUpdate: (ToolState) -> Void

  @State private var parameterValues: [String: JSONValue] = [:]
  @State private var validationErrors: [String: String] = [:]
  @State private var toolResponse: CallToolResponse.Result?
  @State private var isLoading = false
  @State private var rawResponseJSON: JSONValue?
  @State private var rawResponseError: String?
  @State private var hasLoadedOnce = false
  @State private var debounceTask: Task<Void, Never>?
  @State private var focusedField: String?
  @State private var showingFullDescription = false

  @Dependency(\.mcpClientManager) private var mcpClientManager
  @Dependency(\.defaultDatabase) private var database

  // View mode for response
  enum ViewMode: String, CaseIterable {
    case preview = "Preview"
    case raw = "Raw"
  }
  @State private var viewMode: ViewMode = .preview

  var body: some View {
    GeometryReader { geometry in
      VSplitView {
        topPane
          .frame(minHeight: 250, idealHeight: geometry.size.height / 2)

        bottomPane
          .frame(minHeight: 250, idealHeight: geometry.size.height / 2)
      }
    }
    .sheet(isPresented: $showingFullDescription) {
      fullDescriptionSheet
    }
    .onAppear {
      loadFromToolState()
      initializeParameterValues()
    }
    .onChange(of: tool.id) { _, _ in
      // Reset state when tool changes
      parameterValues.removeAll()
      validationErrors.removeAll()
      toolResponse = nil
      rawResponseJSON = nil
      rawResponseError = nil
      hasLoadedOnce = false
      initializeParameterValues()
    }
    .onChange(of: toolState) { _, _ in
      // Update local state when toolState binding changes (e.g., when loading from cache)
      loadFromToolState()
    }
    .onChange(of: parameterValues) { _, _ in
      // Cancel any existing debounce task
      debounceTask?.cancel()

      // Don't update state if we're currently loading (to prevent focus loss)
      if !isLoading {
        // Create a new debounced task
        debounceTask = Task {
          do {
            // Wait for 500ms before updating
            try await Task.sleep(nanoseconds: 500_000_000)

            // Check if task was cancelled
            if !Task.isCancelled {
              await MainActor.run {
                updateToolState()
              }
            }
          } catch {
            // Task was cancelled, ignore
          }
        }
      }
    }
    .onKeyPress(.return, phases: .down) { press in
      if press.modifiers.contains(.command) && canCallTool && !isLoading {
        callTool()
        return .handled
      }
      return .ignored
    }
  }

  @ViewBuilder
  private var topPane: some View {
    VStack(spacing: 0) {
      headerSection
      argumentsSection
    }
  }

  @ViewBuilder
  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        toolInfo
        Spacer()
        annotationBadges
      }
    }
    .padding(20)
    .background(Color(NSColor.controlBackgroundColor))
  }

  @ViewBuilder
  private var toolInfo: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(tool.name)
        .font(.title2)
        .fontWeight(.semibold)

      if let description = tool.description {
        VStack(alignment: .leading, spacing: 4) {
          Text(description)
            .font(.callout)
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .lineLimit(3)

          Button(action: {
            showingFullDescription = true
          }) {
            Text("Show more")
              .font(.caption)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
        }
      } else {
        Button(action: {
          showingFullDescription = true
        }) {
          Text("Show more")
            .font(.caption)
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private var annotationBadges: some View {
    if let annotations = tool.annotations {
      HStack(spacing: 8) {
        if annotations.readOnlyHint == true {
          AnnotationBadge(
            label: "Read Only",
            color: .green,
            icon: "eye"
          )
        }

        if annotations.destructiveHint == true {
          AnnotationBadge(
            label: "Destructive",
            color: .red,
            icon: "exclamationmark.triangle"
          )
        }

        if annotations.idempotentHint == true {
          AnnotationBadge(
            label: "Idempotent",
            color: .blue,
            icon: "arrow.triangle.2.circlepath"
          )
        }

        if annotations.openWorldHint == true {
          AnnotationBadge(
            label: "Open World",
            color: .purple,
            icon: "globe"
          )
        }
      }
    }
  }

  @ViewBuilder
  private var argumentsSection: some View {
    if let properties = tool.inputSchema.properties, !properties.isEmpty {
      argumentsEditor(properties: properties)
    } else {
      noArgumentsView
    }
  }

  @ViewBuilder
  private func argumentsEditor(properties: [String: JSONValue]) -> some View {
    let requiredSet = Set(tool.inputSchema.required ?? [])
    let submitAction: (@Sendable () -> Void)? =
      canCallTool && !isLoading
      ? { @Sendable in
        Task { @MainActor in
          callTool()
        }
      } : nil

    JSONSchemaEditor(
      properties: properties,
      required: requiredSet,
      values: $parameterValues,
      errors: $validationErrors,
      focusedField: $focusedField
    )
    .id(tool.id)  // Stable ID to prevent view recreation
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.toolSubmitAction, submitAction)
  }

  @ViewBuilder
  private var noArgumentsView: some View {
    VStack(spacing: 12) {
      Image(systemName: "function")
        .font(.largeTitle)
        .foregroundColor(.secondary)

      Text("This tool has no arguments")
        .font(.callout)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(NSColor.controlBackgroundColor))
  }

  @ViewBuilder
  private var bottomPane: some View {
    VStack(spacing: 0) {
      responseHeader
      Divider()
      responseContent
    }
  }

  @ViewBuilder
  private var responseHeader: some View {
    HStack {
      Text("Response")
        .font(.headline)

      Spacer()

      ToggleButton(selection: $viewMode)

      Spacer()

      runToolButton
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
    .background(Color(NSColor.controlBackgroundColor))
  }

  @ViewBuilder
  private var runToolButton: some View {
    Button(action: {
      callTool()
    }) {
      ZStack {
        Image(systemName: "play.fill")
          .font(.system(size: 16))
          .foregroundColor(.accentColor)
          .opacity(isLoading ? 0 : 1)

        if isLoading {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.8)
        }
      }
    }
    .buttonStyle(.plain)
    .disabled(!canCallTool || isLoading)
    .help("Run Tool (⌘↩)")
  }

  @ViewBuilder
  private var responseContent: some View {
    if let response = toolResponse {
      Group {
        switch viewMode {
        case .preview:
          let messages = response.content.map { content in
            ToolResponseMessage(content: content)
          }
          MessageThreadView(messages: messages)
        case .raw:
          rawResponseView
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack {
        ContentUnavailableView(
          "No Response",
          systemImage: "function",
          description: Text("Enter arguments and click the ▶ button to call the tool")
        )
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder
  private var rawResponseView: some View {
    if let jsonValue = rawResponseJSON {
      JSONRawView(jsonValue: jsonValue, searchText: "", isSearchActive: false)
    } else if let error = rawResponseError {
      VStack(spacing: 16) {
        Image(systemName: "exclamationmark.triangle")
          .font(.largeTitle)
          .foregroundColor(.red)

        Text("JSON Error")
          .font(.headline)

        Text(error)
          .font(.callout)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      Text("No raw data available")
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func calculateIdealHeight() -> CGFloat {
    let baseHeight: CGFloat = 160  // Header + padding
    let propertiesCount = tool.inputSchema.properties?.count ?? 0
    let propertyHeight: CGFloat = 50  // Height per property
    return baseHeight + (CGFloat(min(propertiesCount, 5)) * propertyHeight)
  }

  private var canCallTool: Bool {
    // Check if all required arguments have values
    guard let required = tool.inputSchema.required else { return true }

    for paramName in required {
      if let value = parameterValues[paramName] {
        // Check if the value is not null or empty
        switch value {
        case .null:
          return false
        case .string(let str) where str.isEmpty:
          return false
        default:
          continue
        }
      } else {
        return false
      }
    }

    return validationErrors.isEmpty
  }

  private func initializeParameterValues() {
    // Initialize default values for all arguments
    if let properties = tool.inputSchema.properties {
      let requiredSet = Set(tool.inputSchema.required ?? [])
      for (key, schema) in properties {
        if parameterValues[key] == nil {
          parameterValues[key] = defaultValueForSchema(
            schema, isRequired: requiredSet.contains(key))
        } else if let currentValue = parameterValues[key] {
          // Validate existing values for enum types
          if case .string = currentValue,
            let enumValues = extractEnum(from: schema),
            !enumValues.isEmpty
          {
            let stringEnums = enumValues.compactMap {
              if case .string(let str) = $0 { return str }
              return nil
            }
            if case .string(let currentStr) = currentValue,
              !stringEnums.contains(currentStr)
            {
              // Current value is not in enum list, reset to first enum value
              if let firstEnum = stringEnums.first {
                parameterValues[key] = .string(firstEnum)
              }
            }
          }
        }
      }
    }
  }

  private func defaultValueForSchema(_ schema: JSONValue, isRequired: Bool = false) -> JSONValue {
    guard let type = extractType(from: schema) else { return .null }

    switch type {
    case "string":
      // Check if this is an enum type
      if let enumValues = extractEnum(from: schema),
        let firstEnum = enumValues.first,
        case .string(let enumStr) = firstEnum
      {
        return .string(enumStr)
      }
      // For required fields, use empty string; for optional, use null
      return isRequired ? .string("") : .null
    case "number":
      return .number(0.0)
    case "integer":
      return .integer(0)
    case "boolean":
      return .boolean(false)
    case "array":
      return .array([])
    case "object":
      return .object([:])
    case "null":
      return .null
    default:
      return .null
    }
  }

  private func extractEnum(from schema: JSONValue) -> [JSONValue]? {
    if case .object(let obj) = schema,
      case .array(let enumValues) = obj["enum"]
    {
      return enumValues
    }
    return nil
  }

  private func extractType(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let typeStr) = obj["type"]
    {
      return typeStr
    }
    return nil
  }

  private func loadFromToolState() {
    parameterValues = toolState.parameterValues
    toolResponse = toolState.toolResponse
    hasLoadedOnce = toolState.hasLoadedOnce
    rawResponseJSON = toolState.rawResponseJSON
    rawResponseError = toolState.rawResponseError
  }

  private func updateToolState(includeParameterValues: Bool = true) {
    // Only update if values actually changed to prevent unnecessary view updates
    let newState = ToolState(
      parameterValues: includeParameterValues ? parameterValues : toolState.parameterValues,
      toolResponse: toolResponse,
      hasLoadedOnce: hasLoadedOnce,
      rawResponseJSON: rawResponseJSON,
      rawResponseError: rawResponseError
    )
    if toolState != newState {
      toolState = newState
      onStateUpdate(newState)
    }
  }

  private func callTool() {
    // Generate arguments for CallToolRequest
    let arguments: [String: JSONValue]? = parameterValues.isEmpty ? nil : parameterValues

    // Save the currently focused field
    let savedFocusedField = focusedField

    // Set loading state
    isLoading = true

    Task { @MainActor in
      do {
        // Get the client and call the tool
        let client = try await mcpClientManager.client(for: server)
        let (content, isError) = try await client.callTool(name: tool.name, arguments: arguments)

        let response = CallToolResponse.Result(content: content, isError: isError)
        toolResponse = response
        hasLoadedOnce = true

        do {
          // TODO: Fix this inefficient encoding/decoding. We do this because we don't have access
          // to the raw JSON responses from the client.
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
          let jsonData = try encoder.encode(response)
          rawResponseJSON = try JSONDecoder().decode(JSONValue.self, from: jsonData)
          rawResponseError = nil
        } catch {
          rawResponseError = error.localizedDescription
          rawResponseJSON = nil
        }

        isLoading = false

        // Update state but preserve focus
        withAnimation(.none) {
          updateToolState(includeParameterValues: false)
        }

        // Ensure focus is maintained
        if let savedField = savedFocusedField {
          focusedField = savedField
        }
      } catch {
        // Create more informative error message
        let errorMessage: String
        let errorDetails: String?

        errorMessage = "Error calling tool: \(error.localizedDescription)"
        errorDetails = nil

        var errorContent: [Content] = [.text(errorMessage)]
        if let details = errorDetails {
          errorContent.append(.text("\n\n💡 \(details)"))
        }

        let errorResponse = CallToolResponse.Result(
          content: errorContent,
          isError: true
        )
        toolResponse = errorResponse
        rawResponseError = error.localizedDescription
        rawResponseJSON = nil
        hasLoadedOnce = true
        isLoading = false

        // Update state but preserve focus
        withAnimation(.none) {
          updateToolState(includeParameterValues: false)
        }

        // Ensure focus is maintained
        if let savedField = savedFocusedField {
          focusedField = savedField
        }
      }
    }
  }

  @ViewBuilder
  private var fullDescriptionSheet: some View {
    VStack(spacing: 20) {
      HStack {
        Text(tool.name)
          .font(.title2)
          .fontWeight(.semibold)

        Spacer()

        Button("Done") {
          showingFullDescription = false
        }
        .keyboardShortcut(.defaultAction)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let description = tool.description {
            Markdown(description)
              .markdownTextStyle {
                ForegroundColor(.primary)
              }
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let properties = tool.inputSchema.properties, !properties.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
              Text("Arguments")
                .font(.headline)

              let requiredSet = Set(tool.inputSchema.required ?? [])
              let sortedProperties = properties.sorted { $0.key < $1.key }

              ForEach(sortedProperties, id: \.key) { key, schema in
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(key)
                      .font(.subheadline)
                      .fontWeight(.medium)

                    if requiredSet.contains(key) {
                      Text("Required")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                          RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.2))
                        )
                        .foregroundColor(.red)
                    }

                    if let type = extractSchemaType(from: schema) {
                      Text(type)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                          RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.2))
                        )
                        .foregroundColor(.blue)
                    }
                  }

                  if let desc = extractDescription(from: schema) {
                    Markdown(desc)
                      .markdownTextStyle {
                        ForegroundColor(.secondary)
                      }
                      .font(.caption)
                      .textSelection(.enabled)
                  }
                }
                .padding(.vertical, 4)
              }
            }
          }

          if let annotations = tool.annotations {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
              Text("Annotations")
                .font(.headline)

              HStack(spacing: 12) {
                if annotations.readOnlyHint == true {
                  AnnotationBadge(
                    label: "Read Only",
                    color: .green,
                    icon: "eye"
                  )
                }

                if annotations.destructiveHint == true {
                  AnnotationBadge(
                    label: "Destructive",
                    color: .red,
                    icon: "exclamationmark.triangle"
                  )
                }

                if annotations.idempotentHint == true {
                  AnnotationBadge(
                    label: "Idempotent",
                    color: .blue,
                    icon: "arrow.triangle.2.circlepath"
                  )
                }

                if annotations.openWorldHint == true {
                  AnnotationBadge(
                    label: "Open World",
                    color: .purple,
                    icon: "globe"
                  )
                }
              }
            }
          }
        }
        .padding(.vertical)
      }
    }
    .padding(20)
    .frame(width: 600, height: 400)
  }

  private func extractSchemaType(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let typeStr) = obj["type"]
    {
      return typeStr
    }
    return nil
  }

  private func extractDescription(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let desc) = obj["description"]
    {
      return desc
    }
    return nil
  }
}
