// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import QuickLook
import SwiftUI

struct EmbeddedResourceView: View {
  let resources: [EmbeddedResource]
  @Binding var viewMode: ResourceViewMode
  let responseJSON: JSONValue?
  let responseError: (any Error)?
  @State private var selectedResource: EmbeddedResource?
  @State private var shareURL: URL?
  @State private var quickLookURL: URL?

  var body: some View {
    HSplitView {
      // Left pane - Resource list
      List(
        resources.indices, id: \.self,
        selection: Binding(
          get: {
            if let selected = selectedResource {
              return resources.firstIndex(where: { resource in
                // Compare the actual resource objects
                switch (resource, selected) {
                case (.text(let r1), .text(let r2)):
                  return r1.uri == r2.uri
                case (.blob(let r1), .blob(let r2)):
                  return r1.uri == r2.uri
                default:
                  return false
                }
              })
            }
            return nil
          },
          set: { index in
            if let index = index, index < resources.count {
              selectResource(resources[index])
            }
          }
        )
      ) { index in
        EmbeddedResourceRow(resource: resources[index])
          .tag(index)
      }
      .listStyle(.inset)
      .frame(minWidth: 100, idealWidth: 200)

      // Right pane - Preview
      VStack(spacing: 0) {
        if let resource = selectedResource {
          // Toolbar
          HStack(spacing: 12) {
            Text(ResourceOperations.resourceTitle(for: resource))
              .font(.headline)
              .foregroundColor(.primary)

            Spacer()

            // Copy button - behavior changes based on view mode
            CopyButton {
              if viewMode == .preview {
                ResourceOperations.copyToClipboard(resource)
              } else {
                copyRawJSONToClipboard()
              }
            }
            .disabled(viewMode == .preview && shouldDisableCopyButton(for: resource))
            .help(viewMode == .preview ? "Copy to clipboard" : "Copy raw JSON to clipboard")

            // Save button
            Button(action: {
              ResourceOperations.saveResource(resource)
            }) {
              Image(systemName: "square.and.arrow.down")
                .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Save to disk")

            // Share button for all content types
            Group {
              switch resource {
              case .text(let textContent):
                ShareLink(item: textContent.text) {
                  Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Share")

              case .blob:
                if let shareURL = shareURL {
                  ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up")
                      .font(.system(size: 14))
                  }
                  .buttonStyle(.plain)
                  .help("Share")
                } else {
                  Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                      .font(.system(size: 14))
                  }
                  .buttonStyle(.plain)
                  .disabled(true)
                  .help("Preparing for share...")
                }
              }
            }

            // Expand button (QuickLook)
            if shareURL != nil {
              Button(action: {
                quickLookURL = shareURL
              }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                  .font(.system(size: 14))
              }
              .buttonStyle(.plain)
              .help("Expand preview")
              .quickLookPreview($quickLookURL)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Color(NSColor.controlBackgroundColor))
          .overlay(
            // Centered toggle buttons
            ToggleButton(
              items: [("Preview", ResourceViewMode.preview), ("Raw", ResourceViewMode.raw)],
              selection: $viewMode
            )
          )

          Divider()

          // Content based on view mode
          if viewMode == .preview {
            PreviewView(resource: resource)
              .transition(.opacity)
          } else {
            // Raw view
            RawDataView(
              responseJSON: responseJSON,
              responseError: responseError
            )
            .transition(.opacity)
          }
        } else {
          ContentUnavailableView(
            "Select a Resource",
            systemImage: "doc.text",
            description: Text("Choose a resource from the list to preview its contents")
          )
        }
      }
      .frame(minWidth: 200, idealWidth: 400)
    }
    .onAppear {
      // Auto-select first resource if none selected
      if selectedResource == nil && !resources.isEmpty {
        selectResource(resources[0])
      }
    }
    .onChange(of: resources) { oldResources, newResources in
      // Only reset selection if the currently selected resource is no longer available
      if let currentSelection = selectedResource {
        let stillExists = newResources.contains { resource in
          switch (resource, currentSelection) {
          case (.text(let r1), .text(let r2)):
            return r1.uri == r2.uri
          case (.blob(let r1), .blob(let r2)):
            return r1.uri == r2.uri
          default:
            return false
          }
        }

        if !stillExists {
          // Current selection no longer exists, select first available
          selectedResource = nil
          if !newResources.isEmpty {
            selectResource(newResources[0])
          }
        }
      } else if !newResources.isEmpty {
        // No current selection, auto-select first
        selectResource(newResources[0])
      }
    }
    .onDisappear {
      // Clean up temporary share URL
      if let shareURL = shareURL {
        try? FileManager.default.removeItem(at: shareURL)
      }
    }
  }

  private func selectResource(_ resource: EmbeddedResource) {
    selectedResource = resource

    // Clean up previous share URL
    if let shareURL = shareURL {
      try? FileManager.default.removeItem(at: shareURL)
      self.shareURL = nil
    }

    // Clear quickLook URL
    quickLookURL = nil

    shareURL = ResourceOperations.createShareURL(for: resource)
  }

  private func shouldDisableCopyButton(for resource: EmbeddedResource) -> Bool {
    switch resource {
    case .text:
      return false
    case .blob(let blobContent):
      // Only enable copy for images in preview mode
      return !(blobContent.mimeType?.starts(with: "image/") ?? false)
    }
  }

  private func copyRawJSONToClipboard() {
    RawDataView.copyRawDataToClipboard(
      responseJSON: responseJSON,
      responseError: responseError
    )
  }
}

struct EmbeddedResourceRow: View {
  let resource: EmbeddedResource

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: iconName)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .frame(width: 16)

        Text(fileName)
          .font(.system(.body, design: .monospaced))
          .lineLimit(1)
          .truncationMode(.middle)
      }

      if let mimeType = mimeType {
        Text(mimeType)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
  }

  private var uri: String {
    switch resource {
    case .text(let content): return content.uri
    case .blob(let content): return content.uri
    }
  }

  private var mimeType: String? {
    switch resource {
    case .text(let content): return content.mimeType
    case .blob(let content): return content.mimeType
    }
  }

  private var fileName: String {
    // Extract filename from URI more robustly
    let uriString = uri

    // Handle different URI formats
    if uriString.contains("?format=") {
      // Special case for URIs with query parameters
      if let baseURI = uriString.split(separator: "?").first {
        return String(baseURI).split(separator: "/").last.map(String.init) ?? uriString
      }
    }

    // Try to parse as URL
    if let url = URL(string: uriString) {
      let path = url.path
      if !path.isEmpty && path != "/" {
        return url.lastPathComponent
      }
    }

    // Fallback to simple string parsing
    return uriString.split(separator: "/").last.map(String.init) ?? uriString
  }

  private var iconName: String {
    guard let mimeType = mimeType else { return "doc" }

    if mimeType.starts(with: "text/") || mimeType == "application/json"
      || mimeType == "application/xml"
    {
      return "doc.text"
    } else if mimeType.starts(with: "image/") {
      return "photo"
    } else if mimeType.starts(with: "audio/") {
      return "speaker.wave.2"
    } else if mimeType.starts(with: "video/") {
      return "video"
    } else {
      return "doc"
    }
  }
}

// Extension to get URI from EmbeddedResource
extension EmbeddedResource {
  var uri: String {
    switch self {
    case .text(let content): return content.uri
    case .blob(let content): return content.uri
    }
  }
}
