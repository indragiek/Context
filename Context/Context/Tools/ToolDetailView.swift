// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import ComposableArchitecture
import ContextCore
import Dependencies
import SwiftUI

struct ToolDetailView: View {
  let tool: Tool
  @Binding var toolState: ToolState
  let server: MCPServer
  let onStateUpdate: (ToolState) -> Void

  @State private var parameterValues: [String: JSONValue] = [:]
  @State private var validationErrors: [String: String] = [:]
  @State private var rawJSONText: String = "{}"
  @State private var jsonParseError: (any Error)?
  @State private var toolResponse: CallToolResponse.Result?
  @State private var isLoading = false
  @State private var responseJSON: JSONValue?
  @State private var responseError: (any Error)?
  @State private var hasLoadedOnce = false
  @State private var debounceTask: Task<Void, Never>?
  @State private var focusedField: String?
  @State private var dynamicPropertyTypes: [String: String] = [:]  // Persists type selections
  @State private var expandedNodes: Set<String> = []  // Persists expansion state
  @State private var dynamicPropertyOrder: [String: [String]] = [:]  // Persists property order
  @State private var showingFullDescription = false
  @State private var showingJSONErrorPopover = false

  @Dependency(\.mcpClientManager) private var mcpClientManager
  @Dependency(\.defaultDatabase) private var database

  @State private var responseViewMode: ToolViewMode = .preview
  @State private var argumentsViewMode: ArgumentsViewMode = .editor

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
      ToolHeaderView(tool: tool, showingFullDescription: $showingFullDescription)
        .fullDescriptionSheet
    }
    .onAppear {
      loadFromToolState()
      initializeParameterValues()
    }
    .onChange(of: tool.id) { _, _ in
      // Reset state when tool changes
      parameterValues.removeAll()
      validationErrors.removeAll()
      rawJSONText = "{}"
      toolResponse = nil
      responseJSON = nil
      responseError = nil
      hasLoadedOnce = false
      initializeParameterValues()
    }
    .onChange(of: toolState) { _, _ in
      // Update local state when toolState binding changes (e.g., when loading from cache)
      loadFromToolState()
    }
    .onChange(of: parameterValues) { _, newValues in
      // Update rawJSONText to keep it in sync
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let jsonValue = JSONValue.object(newValues)
        rawJSONText = try jsonValue.encodeString(encoder: encoder)
        // Clear any JSON parse error since we just generated valid JSON
        jsonParseError = nil
      } catch {
        // This should never happen
        print("Failed to encode parameter values: \(error)")
      }
      
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
      ToolHeaderView(tool: tool, showingFullDescription: $showingFullDescription)
      Divider()
      argumentsHeader
      Divider()
      argumentsSection
    }
  }

  @ViewBuilder
  private var argumentsHeader: some View {
    HStack(spacing: 12) {
      Text("Arguments")
        .font(.headline)
      
      Spacer()
    }
    .padding(.horizontal, 20)
    .frame(height: 50)
    .background(Color(NSColor.controlBackgroundColor))
    .overlay(
      // Centered toggle buttons
      ToggleButton(
        items: [("Editor", ArgumentsViewMode.editor), ("Raw", ArgumentsViewMode.raw)],
        selection: $argumentsViewMode
      )
    )
    .overlay(alignment: .trailing) {
      if jsonParseError != nil {
        Button(action: {
          showingJSONErrorPopover.toggle()
        }) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .popover(isPresented: $showingJSONErrorPopover) {
          if let error = jsonParseError {
            ErrorDetailView(error: error)
          }
        }
      }
    }
  }
  
  @ViewBuilder
  private var argumentsSection: some View {
    switch argumentsViewMode {
    case .editor:
      if let properties = tool.inputSchema.properties, !properties.isEmpty {
        argumentsEditor(properties: properties)
      } else {
        noArgumentsView
      }
    case .raw:
      JSONEditor(
        text: $rawJSONText,
        isEditable: true,
        onValidate: { result in
          switch result {
          case .success(let jsonValue):
            // Clear any previous parse error
            jsonParseError = nil
            
            // Update parameter values from the validated JSON
            switch jsonValue {
            case .object(let dict):
              if parameterValues != dict {
                parameterValues = dict
              }
            case .null:
              // Clear all parameters if null is set
              if !parameterValues.isEmpty {
                parameterValues = [:]
              }
            default:
              // Don't accept non-object JSON for tool parameters
              jsonParseError = JSONEditorError.invalidStructure("Tool parameters must be a JSON object")
              return
            }
          case .failure(let error):
            // JSON is invalid, store the error
            jsonParseError = error
          }
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(NSColor.textBackgroundColor))
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
      rootSchema: .object([
        "type": .string(tool.inputSchema.type),
        "properties": tool.inputSchema.properties.map { .object($0) } ?? .null,
        "required": tool.inputSchema.required.map { .array($0.map { .string($0) }) } ?? .null
      ]),
      values: $parameterValues,
      errors: $validationErrors,
      focusedField: $focusedField,
      dynamicPropertyTypes: $dynamicPropertyTypes,
      expandedNodes: $expandedNodes,
      dynamicPropertyOrder: $dynamicPropertyOrder
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
    ToolResponseView(
      hasLoadedOnce: hasLoadedOnce,
      toolResponse: toolResponse,
      responseJSON: responseJSON,
      responseError: responseError,
      viewMode: $responseViewMode,
      canCallTool: canCallTool,
      isLoading: isLoading,
      onRunTool: callTool
    )
  }

  private var canCallTool: Bool {
    // Check for JSON parse errors first
    if jsonParseError != nil {
      return false
    }
    
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
        // Initialize if the key doesn't exist OR if the value is null
        if parameterValues[key] == nil || (parameterValues[key] != nil && parameterValues[key]!.isNull) {
          let defaultValue = SchemaValueHelpers.defaultValueForSchema(
            schema, isRequired: requiredSet.contains(key))
          parameterValues[key] = defaultValue
        } else if let currentValue = parameterValues[key] {
          // Validate existing values for enum types
          if let enumValues = SchemaValueHelpers.extractEnum(from: schema),
             !enumValues.isEmpty {
            // Check if current value is in the enum list
            var found = false
            for enumValue in enumValues {
              if JSONValueUtilities.jsonValuesEqual(currentValue, enumValue) {
                found = true
                break
              }
            }
            if !found {
              // Current value is not in enum list, reset to first enum value
              if let firstEnum = enumValues.first {
                parameterValues[key] = firstEnum
              }
            }
          }
        }
      }
    }
    // Keep rawJSONText in sync
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let jsonValue = JSONValue.object(parameterValues)
      rawJSONText = try jsonValue.encodeString(encoder: encoder)
    } catch {
      rawJSONText = "{}"
    }
  }

  private func loadFromToolState() {
    parameterValues = toolState.parameterValues
    // Update rawJSONText from parameterValues
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let jsonValue = JSONValue.object(toolState.parameterValues)
      rawJSONText = try jsonValue.encodeString(encoder: encoder)
    } catch {
      rawJSONText = "{}"
    }
    toolResponse = toolState.toolResponse
    hasLoadedOnce = toolState.hasLoadedOnce
    responseJSON = toolState.responseJSON
    responseError = toolState.responseError
  }

  private func updateToolState(includeParameterValues: Bool = true) {
    // Only update if values actually changed to prevent unnecessary view updates
    let newState = ToolState(
      parameterValues: includeParameterValues ? parameterValues : toolState.parameterValues,
      toolResponse: toolResponse,
      hasLoadedOnce: hasLoadedOnce,
      responseJSON: responseJSON,
      responseError: responseError
    )
    if toolState != newState {
      toolState = newState
      onStateUpdate(newState)
    }
  }


  private var filteredParameterValues: [String: JSONValue] {
    parameterValues.compactMapValues { value -> JSONValue? in
      if case .null = value {
        return nil
      }
      return value
    }
  }

  private func callTool() {
    // Generate arguments for CallToolRequest, excluding null values
    let arguments: [String: JSONValue]? = filteredParameterValues.isEmpty ? nil : filteredParameterValues

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
        responseError = nil  // Clear any previous error

        do {
          // TODO: Fix this inefficient encoding/decoding. We do this because we don't have access
          // to the raw JSON responses from the client.
          let jsonData = try JSONUtility.prettyData(from: response)
          responseJSON = try JSONDecoder().decode(JSONValue.self, from: jsonData)
        } catch {
          // If we can't encode the response, keep responseJSON as nil
          responseJSON = nil
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
        // Store the actual error object
        responseError = error

        // Clear the tool response - we'll show error view instead
        toolResponse = nil
        responseJSON = nil

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

}
