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
  @State private var toolResponse: CallToolResponse.Result?
  @State private var isLoading = false
  @State private var responseJSON: JSONValue?
  @State private var responseError: (any Error)?
  @State private var hasLoadedOnce = false
  @State private var debounceTask: Task<Void, Never>?
  @State private var focusedField: String?
  @State private var showingFullDescription = false

  @Dependency(\.mcpClientManager) private var mcpClientManager
  @Dependency(\.defaultDatabase) private var database

  @State private var viewMode: ToolViewMode = .preview

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
      ToolHeaderView(tool: tool, showingFullDescription: $showingFullDescription)
      argumentsSection
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
    ToolResponseView(
      hasLoadedOnce: hasLoadedOnce,
      toolResponse: toolResponse,
      responseJSON: responseJSON,
      responseError: responseError,
      viewMode: $viewMode,
      canCallTool: canCallTool,
      isLoading: isLoading,
      onRunTool: callTool
    )
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
        responseError = nil  // Clear any previous error

        do {
          // TODO: Fix this inefficient encoding/decoding. We do this because we don't have access
          // to the raw JSON responses from the client.
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
          let jsonData = try encoder.encode(response)
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
