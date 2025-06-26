// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Combine
import ComposableArchitecture
import ContextCore
import Dependencies
import GRDB
import MarkdownUI
import SharingGRDB
import SwiftUI

struct ResourceDetailContent: View {
  let resource: Resource
  let server: MCPServer
  @Dependency(\.resourceCache) private var resourceCache
  @Dependency(\.mcpClientManager) private var mcpClientManager
  @Dependency(\.defaultDatabase) private var database
  @State private var embeddedResources: [EmbeddedResource] = []
  @State private var isLoadingResources = false
  @State private var loadingFailed = false
  @State private var hasLoadedOnce = false
  @State private var showingFullDescription = false

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
      .padding(.vertical, 12)
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
        // Show the actual content
        EmbeddedResourceView(resources: embeddedResources)
          .id(resource.uri)  // Force view to recreate when resource changes
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
        let contents = try await client.readResource(uri: resource.uri)

        await MainActor.run {
          embeddedResources = contents
          isLoadingResources = false
          loadingFailed = false
        }

        // Save to cache
        let state = ResourceCacheState(
          variableValues: [:],  // Not used for static resources
          embeddedResources: contents,
          hasLoadedOnce: true,
          lastFetchedURI: resource.uri
        )
        await resourceCache.set(state, for: resource.uri)
      } catch {
        await MainActor.run {
          embeddedResources = []
          isLoadingResources = false
          loadingFailed = true
        }

        // Still save to cache to avoid repeated failed attempts
        let state = ResourceCacheState(
          variableValues: [:],
          embeddedResources: [],
          hasLoadedOnce: true,
          lastFetchedURI: resource.uri
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
