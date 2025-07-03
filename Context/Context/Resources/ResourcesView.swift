// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Combine
import ComposableArchitecture
import ContextCore
import SwiftUI

struct ResourcesView: View {
  let store: StoreOf<ResourcesFeature>
  @State private var selection: String?

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(spacing: 0) {
        // Segmented Control
        if !viewStore.isLoading && viewStore.error == nil && viewStore.hasLoadedOnce {
          Picker(
            "",
            selection: viewStore.binding(
              get: \.selectedSegment,
              send: ResourcesFeature.Action.segmentChanged
            )
          ) {
            ForEach(ResourcesFeature.ResourceSegment.allCases, id: \.self) { segment in
              Text(segment.rawValue).tag(segment)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .padding(.horizontal)
          .padding(.vertical, 8)
          .background(Color(NSColor.controlBackgroundColor))

          Divider()
        }

        Group {
          if viewStore.isLoading {
            ProgressView()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if let error = viewStore.error {
            ContentUnavailableView {
              Label("Failed to Load Resources", systemImage: "exclamationmark.triangle")
            } description: {
              Text(error.localizedDescription)
            } actions: {
              if error.isLikelyConnectionError {
                Button("Reconnect") {
                  viewStore.send(.reconnect)
                }
              }
            }
          } else if (viewStore.selectedSegment == .resources && viewStore.filteredResources.isEmpty)
            || (viewStore.selectedSegment == .templates
              && viewStore.filteredResourceTemplates.isEmpty)
          {
            let itemType = viewStore.selectedSegment == .resources ? "resources" : "templates"
            ContentUnavailableView(
              viewStore.searchQuery.isEmpty ? "No \(itemType.capitalized)" : "No Results",
              systemImage: "folder",
              description: Text(
                viewStore.searchQuery.isEmpty
                  ? "No \(itemType) available" : "No \(itemType) match '\(viewStore.searchQuery)'")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            ScrollViewReader { proxy in
              List(selection: $selection) {
                if viewStore.selectedSegment == .resources {
                  // Show only resources
                  ForEach(viewStore.filteredResources) { resource in
                    ResourceRow(
                      name: resource.name,
                      description: resource.description,
                      uri: resource.uri,
                      mimeType: resource.mimeType,
                      isTemplate: false,
                      isSelected: viewStore.selectedResourceID == resource.id
                    )
                    .tag(resource.id)
                    .id(resource.id)
                    .contextMenu {
                      Button("Copy URI") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resource.uri, forType: .string)
                      }
                    }
                  }
                } else {
                  // Show only templates
                  ForEach(viewStore.filteredResourceTemplates) { template in
                    ResourceRow(
                      name: template.name,
                      description: template.description,
                      uri: template.uriTemplate,
                      mimeType: template.mimeType,
                      isTemplate: true,
                      isSelected: viewStore.selectedResourceTemplateID == template.id
                    )
                    .tag(template.id)
                    .id(template.id)
                    .contextMenu {
                      Button("Copy URI Template") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(template.uriTemplate, forType: .string)
                      }
                    }
                  }
                }
              }
              .onChange(of: viewStore.searchQuery) { _, _ in
                // Reset scroll position to top for any search query change
                if viewStore.selectedSegment == .resources {
                  if let firstResource = viewStore.filteredResources.first {
                    proxy.scrollTo(firstResource.id, anchor: .top)
                  }
                } else {
                  if let firstTemplate = viewStore.filteredResourceTemplates.first {
                    proxy.scrollTo(firstTemplate.id, anchor: .top)
                  }
                }
              }
            }
          }
        }
      }
      .searchable(
        text: viewStore.binding(
          get: \.searchQuery,
          send: ResourcesFeature.Action.searchQueryChanged
        ),
        prompt: viewStore.selectedSegment == .resources
          ? "Search resources..." : "Search resource templates..."
      )
      .onAppear {
        viewStore.send(.onAppear)
      }
      .onChange(of: selection) { _, newValue in
        if let newValue = newValue {
          // Check if it's a resource or template in the filtered lists
          if viewStore.filteredResources.contains(where: { $0.id == newValue }) {
            viewStore.send(.resourceSelected(newValue))
          } else if viewStore.filteredResourceTemplates.contains(where: { $0.id == newValue }) {
            viewStore.send(.resourceTemplateSelected(newValue))
          }
        } else {
          viewStore.send(.resourceSelected(nil))
        }
      }
      .onReceive(viewStore.publisher.selectedResourceID.removeDuplicates()) { newValue in
        if let newValue = newValue, selection != newValue {
          selection = newValue
        } else if newValue == nil && viewStore.selectedResourceTemplateID == nil {
          selection = nil
        }
      }
      .onReceive(viewStore.publisher.selectedResourceTemplateID.removeDuplicates()) { newValue in
        if let newValue = newValue, selection != newValue {
          selection = newValue
        } else if newValue == nil && viewStore.selectedResourceID == nil {
          selection = nil
        }
      }
    }
  }
}

struct ResourceRow: View {
  let name: String?
  let description: String?
  let uri: String
  let mimeType: String?
  let isTemplate: Bool
  let isSelected: Bool

  // Cached regex for template parameters
  private static let templateParameterRegex = /\{[^}]+\}/

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Name and type badge
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text(name ?? "(no name)")
            .font(.system(.body, weight: .medium))
            .foregroundColor(name != nil ? .primary : .secondary)

          if let description = description {
            Text(description)
              .font(.callout)
              .foregroundColor(.secondary)
              .lineLimit(2)
          }
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 4) {
          ResourceTypeLabel(isTemplate: isTemplate, isSelected: isSelected)

          if let mimeType = mimeType {
            Text(mimeType)
              .font(.caption2)
              .fontWeight(.regular)
              .foregroundColor(.secondary)
          }
        }
      }

      // URI
      if isTemplate {
        uriWithBoldedParameters
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      } else {
        Text(uri)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(.vertical, 4)
  }

  private var uriWithBoldedParameters: Text {
    let matches = uri.matches(of: Self.templateParameterRegex)

    var result = Text("")
    var lastIndex = uri.startIndex

    for match in matches {
      // Add text before the parameter
      let beforeText = String(uri[lastIndex..<match.range.lowerBound])
      result = result + Text(beforeText)

      // Add the parameter with bold
      let parameterText = String(uri[match.range])
      result = result + Text(parameterText).fontWeight(.semibold)

      lastIndex = match.range.upperBound
    }

    // Add any remaining text after the last parameter
    if lastIndex < uri.endIndex {
      let remainingText = String(uri[lastIndex...])
      result = result + Text(remainingText)
    }

    return result
  }
}

struct ResourceTypeLabel: View {
  let isTemplate: Bool
  let isSelected: Bool

  var body: some View {
    Text(isTemplate ? "Template" : "Static")
      .font(.caption2)
      .fontWeight(.semibold)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(backgroundColor)
      )
      .foregroundColor(foregroundColor)
  }

  private var backgroundColor: Color {
    if isSelected {
      // Use more opaque backgrounds for better visibility on selection
      return isTemplate ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8)
    } else {
      return isTemplate ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2)
    }
  }

  private var foregroundColor: Color {
    if isSelected {
      // Use white text on selected state for better contrast
      return .white
    } else {
      return isTemplate ? .orange : .blue
    }
  }
}
