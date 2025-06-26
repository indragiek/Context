// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct EmbeddedResourceView: View {
  let resources: [EmbeddedResource]
  @State private var selectedResource: EmbeddedResource?
  @State private var showCopiedIndicator = false
  @State private var copiedIndicatorTask: Task<Void, Never>?
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
            Text(resourceTitle(for: resource))
              .font(.headline)
              .foregroundColor(.primary)

            Spacer()

            // Copy button for text and image content
            Group {
              switch resource {
              case .text(let textContent):
                Button(action: {
                  copyTextToClipboard(textContent.text)
                }) {
                  HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                      .font(.system(size: 14))
                    if showCopiedIndicator {
                      Text("Copied!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .scale))
                    }
                  }
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

              case .blob(let blobContent):
                if let mimeType = blobContent.mimeType, mimeType.starts(with: "image/") {
                  Button(action: {
                    copyImageToClipboard(blobContent.blob)
                  }) {
                    HStack(spacing: 4) {
                      Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                      if showCopiedIndicator {
                        Text("Copied!")
                          .font(.caption)
                          .foregroundColor(.secondary)
                          .transition(.opacity.combined(with: .scale))
                      }
                    }
                  }
                  .buttonStyle(.plain)
                  .help("Copy to clipboard")
                }
              }
            }

            // Save button
            Button(action: {
              saveResource(resource)
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

          Divider()

          // Preview content
          PreviewView(resource: resource)
            .transition(.opacity)
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
      // Cancel any pending animation task
      copiedIndicatorTask?.cancel()
      copiedIndicatorTask = nil

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

    // Create share URL for resources
    switch resource {
    case .text(let textContent):
      createShareURLForText(textContent)
    case .blob(let blobContent):
      createShareURL(for: blobContent)
    }
  }

  private func createShareURLForText(_ textContent: TextResourceContents) {
    // Generate filename from URI
    var fileName = URL(string: textContent.uri)?.lastPathComponent ?? "resource"

    // Ensure filename is not empty or just a path separator
    if fileName.isEmpty || fileName == "/" {
      fileName = "resource"
    }

    // Add appropriate extension based on MIME type
    let fileExtension = FileExtensionHelper.fileExtension(for: textContent.mimeType)
    let fullFileName = fileName.contains(".") ? fileName : "\(fileName)\(fileExtension)"

    // Ensure we have a valid filename
    let safeFileName = fullFileName.isEmpty ? "resource.txt" : fullFileName

    // Create temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let tempURL = tempDir.appendingPathComponent(safeFileName)

    do {
      try textContent.text.write(to: tempURL, atomically: true, encoding: .utf8)
      shareURL = tempURL
    } catch {
      print("Failed to create share URL for text: \(error)")
    }
  }

  private func createShareURL(for blobContent: BlobResourceContents) {
    // Generate filename from URI
    var fileName = URL(string: blobContent.uri)?.lastPathComponent ?? "resource"

    // Ensure filename is not empty or just a path separator
    if fileName.isEmpty || fileName == "/" {
      fileName = "resource"
    }

    // Add appropriate extension based on MIME type
    let fileExtension = FileExtensionHelper.fileExtension(for: blobContent.mimeType)
    let fullFileName = fileName.contains(".") ? fileName : "\(fileName)\(fileExtension)"

    // Ensure we have a valid filename
    let safeFileName = fullFileName.isEmpty ? "resource.bin" : fullFileName

    // Create temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let tempURL = tempDir.appendingPathComponent(safeFileName)

    do {
      try blobContent.blob.write(to: tempURL)
      shareURL = tempURL
    } catch {
      print("Failed to create share URL: \(error)")
    }
  }

  private func fileExtension(for mimeType: String?) -> String {
    FileExtensionHelper.fileExtension(for: mimeType)
  }

  private func resourceTitle(for resource: EmbeddedResource) -> String {
    switch resource {
    case .text(let content):
      return URL(string: content.uri)?.lastPathComponent ?? content.uri
    case .blob(let content):
      return URL(string: content.uri)?.lastPathComponent ?? content.uri
    }
  }

  private func saveResource(_ resource: EmbeddedResource) {
    let savePanel = NSSavePanel()

    // Configure save panel based on resource type
    switch resource {
    case .text(let textContent):
      let fileName = URL(string: textContent.uri)?.lastPathComponent ?? "resource"
      let fileExtension = FileExtensionHelper.fileExtension(for: textContent.mimeType)
      savePanel.nameFieldStringValue =
        fileName.contains(".") ? fileName : "\(fileName)\(fileExtension)"

      if let mimeType = textContent.mimeType {
        switch mimeType {
        case "text/html":
          savePanel.allowedContentTypes = [.html]
        case "application/json":
          savePanel.allowedContentTypes = [.json]
        case "application/xml", "text/xml":
          savePanel.allowedContentTypes = [.xml]
        case "text/css":
          savePanel.allowedContentTypes = [.css]
        case "text/javascript", "application/javascript":
          savePanel.allowedContentTypes = [.javaScript]
        case "text/markdown":
          savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        case "text/csv":
          savePanel.allowedContentTypes = [.commaSeparatedText]
        case "application/x-yaml", "text/yaml":
          savePanel.allowedContentTypes = [.yaml]
        case "text/x-python", "application/x-python-code":
          savePanel.allowedContentTypes = [.pythonScript]
        case "text/x-swift":
          savePanel.allowedContentTypes = [.swiftSource]
        case "text/x-c":
          savePanel.allowedContentTypes = [.cSource]
        case "text/x-c++":
          savePanel.allowedContentTypes = [.cPlusPlusSource]
        case "text/x-ruby":
          savePanel.allowedContentTypes = [.rubyScript]
        case "text/x-php":
          savePanel.allowedContentTypes = [.phpScript]
        default:
          savePanel.allowedContentTypes = [.plainText]
        }
      } else {
        savePanel.allowedContentTypes = [.plainText]
      }

    case .blob(let blobContent):
      let fileName = URL(string: blobContent.uri)?.lastPathComponent ?? "resource"
      let fileExtension = FileExtensionHelper.fileExtension(for: blobContent.mimeType)
      savePanel.nameFieldStringValue =
        fileName.contains(".") ? fileName : "\(fileName)\(fileExtension)"

      // Set allowed content types based on MIME type
      if let mimeType = blobContent.mimeType {
        switch mimeType {
        // Images
        case "image/png":
          savePanel.allowedContentTypes = [.png]
        case "image/jpeg", "image/jpg":
          savePanel.allowedContentTypes = [.jpeg]
        case "image/gif":
          savePanel.allowedContentTypes = [.gif]
        case "image/svg+xml":
          savePanel.allowedContentTypes = [.svg]
        case "image/webp":
          savePanel.allowedContentTypes = [.webP]
        case "image/bmp":
          savePanel.allowedContentTypes = [.bmp]
        case "image/tiff":
          savePanel.allowedContentTypes = [.tiff]
        case "image/x-icon":
          savePanel.allowedContentTypes = [.ico]
        // Videos
        case "video/mp4":
          savePanel.allowedContentTypes = [.mpeg4Movie]
        case "video/quicktime":
          savePanel.allowedContentTypes = [.quickTimeMovie]
        case "video/x-msvideo":
          savePanel.allowedContentTypes = [.avi]
        case "video/mpeg":
          savePanel.allowedContentTypes = [.mpeg]
        // Audio
        case "audio/mpeg", "audio/mp3":
          savePanel.allowedContentTypes = [.mp3]
        case "audio/wav", "audio/x-wav":
          savePanel.allowedContentTypes = [.wav]
        case "audio/aac":
          savePanel.allowedContentTypes = [UTType(filenameExtension: "aac") ?? .audio]
        case "audio/flac":
          savePanel.allowedContentTypes = [UTType(filenameExtension: "flac") ?? .audio]
        case "audio/midi", "audio/x-midi":
          savePanel.allowedContentTypes = [.midi]
        // Documents
        case "application/pdf":
          savePanel.allowedContentTypes = [.pdf]
        case "application/zip":
          savePanel.allowedContentTypes = [.zip]
        default:
          // Try to create UTType from file extension
          let ext = FileExtensionHelper.fileExtension(for: mimeType).trimmingCharacters(
            in: CharacterSet(charactersIn: "."))
          if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            savePanel.allowedContentTypes = [utType]
          } else {
            savePanel.allowedContentTypes = []
          }
        }
      }
    }

    savePanel.canCreateDirectories = true
    savePanel.showsTagField = false
    savePanel.isExtensionHidden = false

    savePanel.begin { response in
      if response == .OK, let url = savePanel.url {
        do {
          switch resource {
          case .text(let textContent):
            try textContent.text.write(to: url, atomically: true, encoding: .utf8)
          case .blob(let blobContent):
            try blobContent.blob.write(to: url)
          }
        } catch {
          print("Failed to save resource: \(error)")
        }
      }
    }
  }

  private func copyTextToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    displayCopiedIndicator()
  }

  private func copyImageToClipboard(_ data: Data) {
    if let image = NSImage(data: data) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([image])
      displayCopiedIndicator()
    }
  }

  private func displayCopiedIndicator() {
    // Cancel any existing task
    copiedIndicatorTask?.cancel()

    // Show indicator
    withAnimation(.easeIn(duration: 0.1)) {
      showCopiedIndicator = true
    }

    // Hide indicator after delay
    copiedIndicatorTask = Task {
      try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds

      if !Task.isCancelled {
        await MainActor.run {
          withAnimation(.easeOut(duration: 0.2)) {
            showCopiedIndicator = false
          }
        }
      }
    }
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
