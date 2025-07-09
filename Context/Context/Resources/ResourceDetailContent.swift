// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import MarkdownUI
import SwiftUI

struct ResourceDetailContent: View {
  let resource: Resource
  let server: MCPServer
  @Dependency(\.resourceCache) private var resourceCache
  @Dependency(\.mcpClientManager) private var mcpClientManager
  @State private var embeddedResources: [EmbeddedResource] = []
  @State private var isLoadingResources = false
  @State private var loadingFailed = false
  @State private var hasLoadedOnce = false
  @State private var showingFullDescription = false
  @State private var viewMode: ResourceViewMode = .preview
  @State private var rawResponseJSON: String? = nil
  @State private var rawResponseError: String? = nil

  var body: some View {
    VStack(spacing: 0) {
      // Fixed header section
      VStack(alignment: .leading, spacing: 16) {
        // Header
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(resource.name ?? "(no name)")
              .font(.title2)
              .fontWeight(.semibold)
              .foregroundColor(resource.name != nil ? .primary : .secondary)

            if let description = resource.description {
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

          Text("Static")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue.opacity(0.2))
            )
            .foregroundColor(.blue)
        }

        Divider()

        // Properties Grid
        VStack(alignment: .leading, spacing: 12) {
          // URI
          PropertyRow(
            label: "URI",
            value: resource.uri,
            icon: "link",
            isMonospaced: true
          )

          // MIME Type
          if let mimeType = resource.mimeType {
            PropertyRow(
              label: "MIME Type",
              value: mimeType,
              icon: "doc.text",
              isMonospaced: true
            )
          }
        }
      }
      .padding(20)
      .background(Color(NSColor.controlBackgroundColor))

      Divider()

      // Fixed Embedded Resources Header
      HStack {
        Text("Embedded Resources")
          .font(.headline)

        Spacer()

        if isLoadingResources {
          ProgressView()
            .controlSize(.small)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
      .background(Color(NSColor.controlBackgroundColor))

      Divider()

      // Embedded Resources Content - always shows the split view
      if isLoadingResources {
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
      } else if loadingFailed || embeddedResources.isEmpty {
        // Show empty state with stable layout
        ContentUnavailableView(
          loadingFailed ? "Failed to Load Resources" : "No Contents Available",
          systemImage: loadingFailed ? "exclamationmark.triangle" : "doc.text",
          description: Text(
            loadingFailed
              ? "Unable to fetch resource contents" : "This resource has no embedded contents")
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
          .id(resource.uri)  // Force view to recreate when resource changes
        }
      }
    }
    .sheet(isPresented: $showingFullDescription) {
      fullDescriptionSheet
    }
    .onAppear {
      loadEmbeddedResources()
    }
    .onChange(of: resource.uri) { _, _ in
      loadEmbeddedResources()
    }
  }

  private func loadEmbeddedResources() {
    Task {
      // First check cache
      let cachedState = await resourceCache.get(for: resource.uri) ?? ResourceCacheState()
      if cachedState.hasLoadedOnce {
        await MainActor.run {
          embeddedResources = cachedState.embeddedResources
          hasLoadedOnce = true
          // viewMode is now global, don't restore from cache
          rawResponseJSON = cachedState.rawResponseJSON
          rawResponseError = cachedState.rawResponseError
          
        }
        return
      }

      // Load resource from MCP server
      await MainActor.run {
        isLoadingResources = true
        hasLoadedOnce = true
      }
      do {
        // Get the client and read the resource
        let client = try await mcpClientManager.client(for: server)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let contents = try await client.readResource(uri: resource.uri)
        
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
          rawResponseJSON = jsonString
          rawResponseError = nil
        }
        
        // Save successful state to cache
        let state = ResourceCacheState(
          variableValues: [:],  // Not used for static resources
          embeddedResources: contents,
          hasLoadedOnce: true,
          lastFetchedURI: resource.uri,
          viewMode: .preview,  // Don't persist viewMode
          rawResponseJSON: jsonString,
          rawResponseError: nil
        )
        await resourceCache.set(state, for: resource.uri)
        
      } catch {
        // Create error response for raw view
        struct ErrorResponse: Encodable {
          struct ErrorInfo: Encodable {
            let code: Int
            let message: String
          }
          let error: ErrorInfo
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let errorResponse = ErrorResponse(
          error: ErrorResponse.ErrorInfo(
            code: -32603,
            message: error.localizedDescription
          )
        )
        
        let jsonData = try? encoder.encode(errorResponse)
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        
        await MainActor.run {
          embeddedResources = []
          isLoadingResources = false
          loadingFailed = true
          rawResponseError = error.localizedDescription
          rawResponseJSON = jsonString
        }
        
        // Save error state to cache to avoid repeated failed attempts
        let state = ResourceCacheState(
          variableValues: [:],
          embeddedResources: [],
          hasLoadedOnce: true,
          lastFetchedURI: resource.uri,
          viewMode: .preview,  // Don't persist viewMode
          rawResponseJSON: jsonString,
          rawResponseError: error.localizedDescription
        )
        await resourceCache.set(state, for: resource.uri)
      }
    }
  }


  @ViewBuilder
  private var fullDescriptionSheet: some View {
    VStack(spacing: 20) {
      HStack {
        Text(resource.name ?? "(no name)")
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
          if let description = resource.description {
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

            PropertyRow(
              label: "URI",
              value: resource.uri,
              icon: "link",
              isMonospaced: true
            )

            if let mimeType = resource.mimeType {
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
