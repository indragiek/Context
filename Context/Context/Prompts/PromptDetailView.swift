// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AVKit
import Combine
import ComposableArchitecture
import ContextCore
import Dependencies
import GRDB
import MarkdownUI
import RegexBuilder
import SharingGRDB
import SwiftUI

// Cached regex for template matching
@MainActor private let templateVarRegex = /\{\{([^}]+)\}\}/
@MainActor private let conditionalRegex = /\{\{([#^])([^}]+)\}\}(.*?)\{\{\/\2\}\}/

struct PromptDetailView: View {
  let prompt: Prompt
  let server: MCPServer
  let promptState: PromptState
  let onStateUpdate: (PromptState) -> Void

  @State private var isLoadingMessages = false
  @State private var loadingFailed = false
  @FocusState private var focusedArgument: String?
  @State private var fetchTask: Task<Void, Never>?
  @State private var showingFullDescription = false

  @State private var argumentValues: [String: String]
  @State private var messages: [PromptMessage]
  @State private var hasLoadedOnce: Bool

  enum ViewMode: String, CaseIterable {
    case preview = "Preview"
    case raw = "Raw"
  }
  @State private var viewMode: ViewMode = .preview

  @State private var rawResponse: GetPromptResponse.Result?
  @State private var rawResponseJSON: JSONValue?
  @State private var rawResponseError: String?
  @State private var fetchError: (any Error)?

  init(
    prompt: Prompt, server: MCPServer, promptState: PromptState,
    onStateUpdate: @escaping (PromptState) -> Void
  ) {
    self.prompt = prompt
    self.server = server
    self.promptState = promptState
    self.onStateUpdate = onStateUpdate

    self._argumentValues = State(initialValue: promptState.argumentValues)
    self._messages = State(initialValue: promptState.messages)
    self._hasLoadedOnce = State(initialValue: promptState.hasLoadedOnce)
    self._rawResponseJSON = State(initialValue: promptState.rawResponseJSON)
    self._rawResponseError = State(initialValue: promptState.rawResponseError)
  }

  var body: some View {
    VSplitView {
      // Top pane - Header and arguments
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Header
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(prompt.name)
                .font(.title2)
                .fontWeight(.semibold)

              if let description = prompt.description {
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

            Spacer()
          }

          Divider()

          // Arguments Section
          if let arguments = prompt.arguments, !arguments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("Arguments")
                .font(.headline)

              VStack(alignment: .leading, spacing: 8) {
                ForEach(arguments, id: \.name) { argument in
                  HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                      Image(systemName: "curlybraces")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                      Text(argument.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .help(argument.description ?? "")
                    }
                    .frame(width: 120, alignment: .leading)

                    TextField(
                      argument.required == true ? "Required" : "Optional",
                      text: Binding(
                        get: { argumentValues[argument.name] ?? "" },
                        set: {
                          argumentValues[argument.name] = $0
                          updatePromptState()
                        }
                      )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .focused($focusedArgument, equals: argument.name)
                    .foregroundColor(
                      argument.required == true
                        && !(argumentValues[argument.name] ?? "").trimmingCharacters(
                          in: .whitespacesAndNewlines
                        ).isEmpty
                        ? .primary : (argument.required == true ? .red : .primary)
                    )
                    .onSubmit {
                      if allRequiredArgumentsFilled && !isLoadingMessages {
                        fetchPromptMessages()
                      }
                    }
                  }
                }
              }
            }
          } else {
            Text("This prompt has no arguments")
              .font(.callout)
              .foregroundColor(.secondary)
          }

          Spacer()
        }
        .padding(20)
      }
      .background(Color(NSColor.controlBackgroundColor))
      .frame(minHeight: 200, idealHeight: max(200, calculateIdealHeight()))

      // Bottom pane - Messages
      VStack(spacing: 0) {
        // Fixed Messages Header
        HStack {
          Text("Messages")
            .font(.headline)

          Spacer()

          ToggleButton(selection: $viewMode)

          Spacer()

          ZStack {
            ProgressView()
              .controlSize(.small)
              .opacity(isLoadingMessages ? 1 : 0)
          }
          .frame(width: 20)

          Button(action: {
            fetchPromptMessages()
          }) {
            Image(systemName: "square.and.arrow.down")
              .font(.system(size: 14))
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
          .disabled(isLoadingMessages || !allRequiredArgumentsFilled)
          .help(
            allRequiredArgumentsFilled
              ? "Get prompt messages" : "Fill in all required arguments to continue")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))

        Divider()

        // Messages Content
        if !hasLoadedOnce && prompt.arguments?.isEmpty == false {
          ContentUnavailableView(
            "No Messages",
            systemImage: "arrow.down.message",
            description: Text("Enter arguments and click the 􀈄 button to load messages")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoadingMessages {
          ProgressView()
            .controlSize(.regular)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadingFailed {
          if let error = fetchError {
            errorView(for: error)
          } else {
            ContentUnavailableView(
              "Failed to Load Messages",
              systemImage: "exclamationmark.triangle",
              description: Text("Unable to fetch prompt messages")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        } else if messages.isEmpty {
          ContentUnavailableView(
            "No Messages Available",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("This prompt has no messages")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          // Show either preview or raw view based on selection
          Group {
            switch viewMode {
            case .preview:
              PromptMessagesList(messages: messages, argumentValues: argumentValues)
            case .raw:
              rawView()
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(minHeight: 350)
    }
    .sheet(isPresented: $showingFullDescription) {
      fullDescriptionSheet
    }
    .onAppear {
      if let arguments = prompt.arguments {
        for argument in arguments {
          if argumentValues[argument.name] == nil {
            argumentValues[argument.name] = ""
          }
        }
      }

      if prompt.arguments == nil && !hasLoadedOnce {
        fetchPromptMessages()
      }
    }
    .onDisappear {
      fetchTask?.cancel()
      fetchTask = nil
    }
  }

  private func updatePromptState() {
    let newState = PromptState(
      argumentValues: argumentValues,
      messages: messages,
      hasLoadedOnce: hasLoadedOnce,
      rawResponseJSON: rawResponseJSON,
      rawResponseError: rawResponseError
    )
    onStateUpdate(newState)
  }

  private var allRequiredArgumentsFilled: Bool {
    guard let arguments = prompt.arguments else { return true }

    return arguments.allSatisfy { argument in
      if argument.required == true {
        // Check for meaningful content (not just whitespace)
        let value = argumentValues[argument.name] ?? ""
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      return true
    }
  }

  private func calculateIdealHeight() -> CGFloat {
    let baseHeight: CGFloat = 160  // Header + padding
    let argumentHeight: CGFloat = 40  // Height per argument input
    let argumentsCount = min(prompt.arguments?.count ?? 0, 3)  // Size for up to 3 arguments
    return baseHeight + (CGFloat(argumentsCount) * argumentHeight)
  }

  private func fetchPromptMessages() {
    @Dependency(\.mcpClientManager) var mcpClientManager
    @Dependency(\.defaultDatabase) var database

    // Cancel any existing task
    fetchTask?.cancel()

    isLoadingMessages = true

    fetchTask = Task { @MainActor in
      do {
        let client = try await mcpClientManager.client(for: server)

        if Task.isCancelled { return }

        let (description, fetchedMessages) = try await client.getPrompt(
          name: prompt.name, arguments: argumentValues)

        if Task.isCancelled { return }

        await MainActor.run {
          rawResponse = GetPromptResponse.Result(
            description: description, messages: fetchedMessages)

          do {
            // TODO: Fix this inefficient encoding/decoding. We do this because we don't have access
            // to the raw JSON responses from the client.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let jsonData = try JSONEncoder().encode(rawResponse)
            rawResponseJSON = try JSONDecoder().decode(JSONValue.self, from: jsonData)
            rawResponseError = nil
          } catch {
            rawResponseJSON = nil
            rawResponseError = "Failed to encode/decode JSON: \(error.localizedDescription)"
          }

          messages = fetchedMessages.map { message in
            PromptMessage(
              role: message.role,
              content: replaceTemplateVariables(in: message.content)
            )
          }

          isLoadingMessages = false
          loadingFailed = false
          hasLoadedOnce = true
          fetchError = nil

          updatePromptState()
        }
      } catch {
        if Task.isCancelled { return }

        await MainActor.run {
          messages = []
          rawResponse = nil
          rawResponseJSON = nil
          rawResponseError = error.localizedDescription
          fetchError = error
          isLoadingMessages = false
          loadingFailed = true
          hasLoadedOnce = true

          updatePromptState()
        }
      }
    }
  }

  private func replaceTemplateVariables(in content: Content) -> Content {
    switch content {
    case .text(let text, let annotations):
      var processedText = text

      var iterationCount = 0
      let maxIterations = 10

      // Replace simple template variables {{key}} with actual values
      processedText = processedText.replacing(templateVarRegex) { match in
        iterationCount += 1
        guard iterationCount < maxIterations else {
          return String(match.output.0)
        }

        let key = String(match.output.1).trimmingCharacters(in: .whitespaces)
        if let value = argumentValues[key], !value.isEmpty {
          return value
        }
        return String(match.output.0)
      }

      // Handle conditional sections {{#key}}...{{/key}} and {{^key}}...{{/key}}
      iterationCount = 0
      processedText = processedText.replacing(conditionalRegex) { match in
        iterationCount += 1
        guard iterationCount < maxIterations else {
          // Too many replacements, likely malformed template
          return String(match.output.0)
        }

        let conditionType = String(match.output.1)  // "#" or "^"
        let key = String(match.output.2).trimmingCharacters(in: .whitespaces)
        let content = String(match.output.3)

        let hasValue =
          argumentValues[key].map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
          ?? false

        if conditionType == "#" {
          return hasValue ? content : ""
        } else {
          return hasValue ? "" : content
        }
      }

      return .text(processedText, annotations: annotations)

    case .resource(let embeddedResource, let annotations):
      switch embeddedResource {
      case .text(let textResource):
        var processedURI = textResource.uri
        var processedText = textResource.text

        processedURI = textResource.uri.replacing(templateVarRegex) { match in
          let key = String(match.output.1).trimmingCharacters(in: .whitespaces)
          return argumentValues[key] ?? String(match.output.0)
        }

        processedText = textResource.text.replacing(templateVarRegex) { match in
          let key = String(match.output.1).trimmingCharacters(in: .whitespaces)
          return argumentValues[key] ?? String(match.output.0)
        }

        return .resource(
          .text(
            TextResourceContents(
              uri: processedURI,
              mimeType: textResource.mimeType,
              text: processedText
            )),
          annotations: annotations
        )

      case .blob(let blobResource):
        var processedURI = blobResource.uri

        processedURI = blobResource.uri.replacing(templateVarRegex) { match in
          let key = String(match.output.1).trimmingCharacters(in: .whitespaces)
          return argumentValues[key] ?? String(match.output.0)
        }

        return .resource(
          .blob(
            BlobResourceContents(
              uri: processedURI,
              mimeType: blobResource.mimeType,
              blob: blobResource.blob
            )),
          annotations: annotations
        )
      }

    default:
      return content
    }
  }
  
  @ViewBuilder
  private func errorView(for error: any Error) -> some View {
    if let clientError = error as? ClientError {
      switch clientError {
      case .requestFailed(_, let jsonRPCError):
        ContentUnavailableView {
          Label("Request Failed", systemImage: "exclamationmark.triangle")
        } description: {
          VStack(alignment: .leading, spacing: 8) {
            Text("Error \(jsonRPCError.error.code): \(jsonRPCError.error.message)")
              .font(.callout)
              .foregroundColor(.secondary)
            
            if let data = jsonRPCError.error.data {
              Text("Details:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.top, 4)
              
              Text(formatJSONValuePreview(data))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            }
          }
          .multilineTextAlignment(.leading)
          .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
      case .requestInvalidResponse(_, let underlyingError, let data):
        ContentUnavailableView {
          Label("Invalid Response", systemImage: "exclamationmark.triangle")
        } description: {
          VStack(alignment: .leading, spacing: 8) {
            Text(underlyingError.localizedDescription)
              .font(.callout)
              .foregroundColor(.secondary)
            
            if let stringData = String(data: data, encoding: .utf8) {
              Text("Response data:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.top, 4)
              
              Text(stringData)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            }
          }
          .multilineTextAlignment(.leading)
          .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
      default:
        ContentUnavailableView(
          "Error",
          systemImage: "exclamationmark.triangle",
          description: Text(error.localizedDescription)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    } else {
      ContentUnavailableView(
        "Error",
        systemImage: "exclamationmark.triangle",
        description: Text(error.localizedDescription)
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
  
  @ViewBuilder
  private func rawView() -> some View {
    if let error = fetchError as? ClientError {
      switch error {
      case .requestFailed(_, let jsonRPCError):
        // For requestFailed, show the JSONRPCError in JSONRawView
        if let jsonData = try? JSONEncoder().encode(jsonRPCError),
           let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData) {
          JSONRawView(jsonValue: jsonValue, searchText: "", isSearchActive: false)
        } else {
          errorPlaceholder()
        }
        
      case .requestInvalidResponse(_, _, let data):
        // For invalid response, check if the data is valid JSON
        if let stringData = String(data: data, encoding: .utf8) {
          if isLikelyJSON(stringData) {
            // Try to parse as JSON
            if let jsonData = stringData.data(using: .utf8),
               let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData) {
              JSONRawView(jsonValue: jsonValue, searchText: "", isSearchActive: false)
            } else {
              // Show as plain text if JSON parsing fails
              ScrollView {
                Text(stringData)
                  .font(.system(.body, design: .monospaced))
                  .textSelection(.enabled)
                  .padding()
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          } else {
            // Show as plain text if not JSON-like
            ScrollView {
              Text(stringData)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        } else {
          errorPlaceholder()
        }
        
      default:
        errorPlaceholder()
      }
    } else if let jsonValue = rawResponseJSON {
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
  
  @ViewBuilder
  private func errorPlaceholder() -> some View {
    ContentUnavailableView(
      "No Error Object",
      systemImage: "xmark.circle",
      description: Text("An error object was not returned by the server")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  
  private func formatJSONValuePreview(_ value: JSONValue) -> String {
    switch value {
    case .string(let str):
      return str
    case .number(let num):
      return String(num)
    case .integer(let int):
      return String(int)
    case .boolean(let bool):
      return String(bool)
    case .null:
      return "null"
    case .array(let arr):
      return "[\(arr.count) items]"
    case .object(let obj):
      return "{\(obj.count) properties}"
    }
  }
  
  private func isLikelyJSON(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
  }
}

struct PromptMessagesList: View {
  let messages: [PromptMessage]
  let argumentValues: [String: String]

  var body: some View {
    MessageThreadView(messages: messages)
  }
}

extension PromptDetailView {
  @ViewBuilder
  private var fullDescriptionSheet: some View {
    VStack(spacing: 20) {
      HStack {
        Text(prompt.name)
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
          if let description = prompt.description {
            Markdown(description)
              .markdownTextStyle {
                ForegroundColor(.primary)
              }
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let arguments = prompt.arguments, !arguments.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
              Text("Arguments")
                .font(.headline)

              ForEach(arguments, id: \.name) { argument in
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(argument.name)
                      .font(.subheadline)
                      .fontWeight(.medium)

                    if argument.required ?? false {
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
                  }

                  if let desc = argument.description {
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
        }
        .padding(.vertical)
      }
    }
    .padding(20)
    .frame(width: 600, height: 400)
  }
}
