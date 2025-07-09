// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import MarkdownUI
import SwiftUI

struct ResourceTemplateDetailContent: View {
  let template: ResourceTemplate
  let server: MCPServer
  @Dependency(\.resourceCache) private var resourceCache
  @Dependency(\.mcpClientManager) private var mcpClientManager
  @State private var isLoadingResources = false
  @State private var loadingFailed = false
  @FocusState private var focusedVariable: String?

  // Local state that syncs with cache
  @State private var variableValues: [String: String] = [:]
  @State private var embeddedResources: [EmbeddedResource] = []
  @State private var hasLoadedOnce = false
  @State private var lastFetchedURI: String? = nil
  @State private var showingFullDescription = false
  @State private var viewMode: ResourceViewMode = .preview
  @State private var rawResponseJSON: String? = nil
  @State private var rawResponseError: String? = nil

  // Cached regex for template parameters
  private static let templateParameterRegex = /\{[^}]+\}/

  var body: some View {
    VSplitView {
      // Top pane - Header and template variables
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Header
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(template.name)
                .font(.title2)
                .fontWeight(.semibold)

              if let description = template.description {
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

            Text("Template")
              .font(.caption2)
              .fontWeight(.medium)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(
                RoundedRectangle(cornerRadius: 4)
                  .fill(Color.orange.opacity(0.2))
              )
              .foregroundColor(.orange)
          }

          Divider()

          // Properties
          VStack(alignment: .leading, spacing: 12) {
            // URI Template with bolded parameters
            HStack(alignment: .top, spacing: 8) {
              HStack(spacing: 6) {
                Image(systemName: "text.badge.plus")
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .frame(width: 16)

                Text("URI Template")
                  .font(.caption)
                  .fontWeight(.medium)
                  .foregroundColor(.secondary)
              }
              .frame(width: 100, alignment: .leading)

              uriTemplateWithBoldedParameters
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundColor(.primary)
            }

            // MIME Type
            if let mimeType = template.mimeType {
              PropertyRow(
                label: "MIME Type",
                value: mimeType,
                icon: "doc.text",
                isMonospaced: true
              )
            }

            // Annotations
            if let annotations = template.annotations {
              HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 6) {
                  Image(systemName: "tag")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                  Text("Annotations")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                }
                .frame(width: 100, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                  if let audience = annotations.audience {
                    HStack(spacing: 6) {
                      Text("Audience:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                      ForEach(audience, id: \.self) { role in
                        Text(role.rawValue)
                          .font(.caption2)
                          .padding(.horizontal, 6)
                          .padding(.vertical, 2)
                          .background(
                            RoundedRectangle(cornerRadius: 3)
                              .fill(Color.indigo.opacity(0.2))
                          )
                          .foregroundColor(.indigo)
                      }
                    }
                  }

                  if let priority = annotations.priority {
                    HStack(spacing: 4) {
                      Text("Priority:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                      Text("\(priority, specifier: "%.1f")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                    }
                  }
                }
              }
            }
          }

          // Variable Input Section
          let variables = extractTemplateVariables(from: template.uriTemplate)
          if !variables.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 12) {
              Text("Template Variables")
                .font(.headline)

              VStack(alignment: .leading, spacing: 8) {
                ForEach(variables, id: \.self) { variable in
                  HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                      Image(systemName: "curlybraces")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                      Text(variable)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    }
                    .frame(width: 100, alignment: .leading)

                    TextField(
                      "Enter value",
                      text: Binding(
                        get: { variableValues[variable] ?? "" },
                        set: { newValue in
                          variableValues[variable] = newValue
                          // Save the updated state to cache
                          Task {
                            await saveToCacheForTemplate(template.uriTemplate)
                          }
                        }
                      )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .focused($focusedVariable, equals: variable)
                    .onSubmit {
                      if allVariablesFilled && !isLoadingResources {
                        fetchEmbeddedResources()
                      }
                    }
                  }
                }
              }
            }
          }

          Spacer(minLength: 0)
        }
        .padding(20)
      }
      .background(Color(NSColor.controlBackgroundColor))
      .frame(minHeight: 250, idealHeight: calculateIdealHeight())

      // Bottom pane - Embedded Resources
      VStack(spacing: 0) {
        // Fixed Embedded Resources Header
        HStack {
          Text("Embedded Resources")
            .font(.headline)

          Spacer()

          HStack(spacing: 8) {
            ZStack {
              ProgressView()
                .controlSize(.small)
                .opacity(isLoadingResources ? 1 : 0)
            }
            .frame(width: 20)


            // Only show button if there are template variables
            let variables = extractTemplateVariables(from: template.uriTemplate)
            if !variables.isEmpty {
              Button(action: {
                fetchEmbeddedResources()
              }) {
                Image(systemName: "square.and.arrow.down")
                  .font(.system(size: 14))
                  .foregroundColor(.accentColor)
              }
              .buttonStyle(.plain)
              .disabled(isLoadingResources || !allVariablesFilled)
              .help(
                allVariablesFilled ? "Fetch embedded resources" : "Fill in all variables to continue")
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))

        Divider()

        // Embedded Resources Content
        if !hasLoadedOnce {
          ContentUnavailableView(
            "No Resources",
            systemImage: "ellipsis.curlybraces",
            description: Text(
              "Enter template variables and click the 􀈄 button to load messages")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoadingResources {
          // Show loading state with stable layout
          HSplitView {
            // Left pane - loading
            ProgressView()
              .controlSize(.regular)
              .frame(minWidth: 100, idealWidth: 200)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(NSColor.controlBackgroundColor))

            // Right pane - also loading
            ProgressView()
              .controlSize(.regular)
              .frame(minWidth: 200, idealWidth: 400)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        } else if loadingFailed {
          // Show error state
          ContentUnavailableView(
            "Failed to Load Resources",
            systemImage: "exclamationmark.triangle",
            description: Text("Unable to fetch resource contents")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if embeddedResources.isEmpty {
          // Show empty state with the constructed URI for debugging
          let uri = constructURI(with: variableValues)
          ContentUnavailableView(
            "No Contents Found",
            systemImage: "doc.text",
            description: Text("No embedded resources found for:\n\(uri)")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          // Show the actual content - EmbeddedResourceView now handles view mode switching
          if rawResponseError != nil {
            ContentUnavailableView {
              Label("Error Loading Resource", systemImage: "exclamationmark.triangle")
            } description: {
              if let errorMessage = rawResponseError {
                Text(errorMessage)
                  .font(.callout)
                  .foregroundColor(.secondary)
                  .multilineTextAlignment(.center)
              }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            EmbeddedResourceView(
              resources: embeddedResources,
              viewMode: $viewMode,
              rawJSON: rawResponseJSON
            )
            .id(template.uriTemplate)  // Force view to recreate when template changes
          }
        }
      }
      .frame(minHeight: 300)
    }
    .sheet(isPresented: $showingFullDescription) {
      fullDescriptionSheet
    }
    .onAppear {
      // Load cached state for this template
      loadCachedState()
    }
    .onChange(of: template.uriTemplate) { oldValue, newValue in
      Task {
        // Save current state to cache before switching
        if !oldValue.isEmpty {
          await saveToCacheForTemplate(oldValue)
        }

        // Load cached state for new template
        loadCachedState()
      }
    }
    .onChange(of: viewMode) { _, newValue in
      // Save the new view mode to cache
      Task {
        let state = await resourceCache.get(for: template.uriTemplate) ?? ResourceCacheState()
        var updatedState = state
        updatedState.viewMode = newValue
        await resourceCache.set(updatedState, for: template.uriTemplate)
      }
    }
  }

  private var uriTemplateWithBoldedParameters: Text {
    let matches = template.uriTemplate.matches(of: Self.templateParameterRegex)

    var result = Text("")
    var lastIndex = template.uriTemplate.startIndex

    for match in matches {
      // Add text before the parameter
      let beforeText = String(template.uriTemplate[lastIndex..<match.range.lowerBound])
      result = result + Text(beforeText)

      // Add the parameter with bold
      let parameterText = String(template.uriTemplate[match.range])
      result = result + Text(parameterText).fontWeight(.semibold)

      lastIndex = match.range.upperBound
    }

    // Add any remaining text after the last parameter
    if lastIndex < template.uriTemplate.endIndex {
      let remainingText = String(template.uriTemplate[lastIndex...])
      result = result + Text(remainingText)
    }

    return result
  }

  private func loadCachedState() {
    Task {
      let state = await resourceCache.get(for: template.uriTemplate) ?? ResourceCacheState()
      await MainActor.run {
        variableValues = state.variableValues
        embeddedResources = state.embeddedResources
        hasLoadedOnce = state.hasLoadedOnce
        lastFetchedURI = state.lastFetchedURI
        viewMode = state.viewMode
        rawResponseJSON = state.rawResponseJSON
        rawResponseError = state.rawResponseError
        
      }
    }
  }

  private func saveToCacheForTemplate(_ templateURI: String) async {
    let state = ResourceCacheState(
      variableValues: variableValues,
      embeddedResources: embeddedResources,
      hasLoadedOnce: hasLoadedOnce,
      lastFetchedURI: lastFetchedURI,
      viewMode: viewMode,
      rawResponseJSON: rawResponseJSON,
      rawResponseError: rawResponseError
    )
    await resourceCache.set(state, for: templateURI)
  }

  private var allVariablesFilled: Bool {
    let variables = extractTemplateVariables(from: template.uriTemplate)
    return variables.allSatisfy { variable in
      !(variableValues[variable] ?? "").isEmpty
    }
  }

  private func calculateIdealHeight() -> CGFloat {
    let variables = extractTemplateVariables(from: template.uriTemplate)
    let baseHeight: CGFloat = 280  // Header + properties + padding
    let variableHeight: CGFloat = 40  // Height per variable input
    let variablesCount = min(variables.count, 3)  // Show up to 3 variables by default
    return baseHeight + (CGFloat(variablesCount) * variableHeight)
  }

  private func fetchEmbeddedResources() {
    // Build the URI from template and variables
    let uri = constructURI(with: variableValues)

    // Check if we already have resources for this exact URI
    if let lastURI = lastFetchedURI, lastURI == uri {
      // Already have the resources for this URI, no need to fetch again
      return
    }

    // Load resource from MCP server
    isLoadingResources = true
    hasLoadedOnce = true

    Task {
      do {
        // Get the client and read the resource
        let client = try await mcpClientManager.client(for: server)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let contents = try await client.readResource(uri: uri)
        
        // Create the response structure for raw view
        // Encode contents directly as the Result would contain just this
        let responseToEncode = ["contents": contents]
        
        // Encode the raw response
        let jsonData = try encoder.encode(responseToEncode)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "null"
        
        await MainActor.run {
          embeddedResources = contents
          isLoadingResources = false
          loadingFailed = false
          lastFetchedURI = uri
          rawResponseJSON = jsonString
          rawResponseError = nil

          // Save the fetched resources to cache
          Task {
            await saveToCacheForTemplate(template.uriTemplate)
          }
        }
      } catch {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        // Create error response for raw view
        struct ErrorResponse: Encodable {
          struct ErrorInfo: Encodable {
            let code: Int
            let message: String
          }
          let error: ErrorInfo
        }
        
        let errorResponse = ErrorResponse(
          error: ErrorResponse.ErrorInfo(
            code: -32603,
            message: error.localizedDescription
          )
        )
        
        // Encode the error for raw view
        let jsonData = try? encoder.encode(errorResponse)
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        
        await MainActor.run {
          embeddedResources = []
          isLoadingResources = false
          loadingFailed = true
          lastFetchedURI = uri
          rawResponseError = error.localizedDescription
          rawResponseJSON = jsonString

          // Still save to cache to avoid repeated failed attempts
          Task {
            await saveToCacheForTemplate(template.uriTemplate)
          }
        }
      }
    }
  }

  private func constructURI(with values: [String: String]) -> String {
    var uri = template.uriTemplate
    for (variable, value) in values {
      uri = uri.replacingOccurrences(of: "{\(variable)}", with: value)
    }
    return uri
  }


  private func extractTemplateVariables(from template: String) -> [String] {
    let pattern = #"\{([^}]+)\}"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let matches =
      regex?.matches(in: template, range: NSRange(template.startIndex..., in: template)) ?? []

    return matches.compactMap { match in
      guard let range = Range(match.range(at: 1), in: template) else { return nil }
      return String(template[range])
    }
  }

  @ViewBuilder
  private var fullDescriptionSheet: some View {
    VStack(spacing: 20) {
      HStack {
        Text(template.name)
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
          if let description = template.description {
            Markdown(description)
              .markdownTextStyle {
                ForegroundColor(.primary)
              }
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          Divider()

          VStack(alignment: .leading, spacing: 8) {
            Text("Properties")
              .font(.headline)

            // URI Template
            HStack(alignment: .top, spacing: 8) {
              HStack(spacing: 6) {
                Image(systemName: "text.badge.plus")
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .frame(width: 16)

                Text("URI Template")
                  .font(.caption)
                  .fontWeight(.medium)
                  .foregroundColor(.secondary)
              }
              .frame(width: 100, alignment: .leading)

              uriTemplateWithBoldedParameters
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundColor(.primary)
            }

            if let mimeType = template.mimeType {
              PropertyRow(
                label: "MIME Type",
                value: mimeType,
                icon: "doc.text",
                isMonospaced: true
              )
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
