// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct EmbeddedResourceContentView: View {
  let resource: EmbeddedResource
  @State private var showCopiedIndicator = false
  @State private var copiedIndicatorTask: Task<Void, Never>?
  @State private var shareURL: URL?
  @State private var quickLookURL: URL?

  var body: some View {
    VStack(spacing: 0) {
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
    }
    .onAppear {
      prepareShareURL()
    }
    .onDisappear {
      // Clean up temporary share URL
      if let shareURL = shareURL {
        try? FileManager.default.removeItem(at: shareURL)
      }
    }
  }

  private func prepareShareURL() {
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
    let fileExtension = fileExtension(for: textContent.mimeType)
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
    let fileExtension = fileExtension(for: blobContent.mimeType)
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
    guard let mimeType = mimeType else { return "" }

    switch mimeType {
    // Text formats
    case "text/plain": return ".txt"
    case "text/html": return ".html"
    case "text/css": return ".css"
    case "text/javascript", "application/javascript": return ".js"
    case "text/markdown": return ".md"
    case "text/csv": return ".csv"
    case "text/xml": return ".xml"
    // Application formats
    case "application/json": return ".json"
    case "application/xml": return ".xml"
    case "application/pdf": return ".pdf"
    case "application/zip": return ".zip"
    case "application/x-yaml", "text/yaml": return ".yaml"
    // Images
    case "image/png": return ".png"
    case "image/jpeg", "image/jpg": return ".jpg"
    case "image/gif": return ".gif"
    case "image/svg+xml": return ".svg"
    case "image/webp": return ".webp"
    case "image/bmp": return ".bmp"
    case "image/tiff": return ".tiff"
    case "image/x-icon": return ".ico"
    // Videos
    case "video/mp4": return ".mp4"
    case "video/quicktime": return ".mov"
    case "video/x-msvideo": return ".avi"
    case "video/webm": return ".webm"
    case "video/mpeg": return ".mpeg"
    case "video/ogg": return ".ogv"
    // Audio
    case "audio/mpeg", "audio/mp3": return ".mp3"
    case "audio/wav", "audio/x-wav": return ".wav"
    case "audio/ogg": return ".ogg"
    case "audio/aac": return ".aac"
    case "audio/flac": return ".flac"
    case "audio/webm": return ".weba"
    case "audio/midi", "audio/x-midi": return ".midi"
    // Programming languages
    case "text/x-python", "application/x-python-code": return ".py"
    case "text/x-java-source": return ".java"
    case "text/x-c": return ".c"
    case "text/x-c++": return ".cpp"
    case "text/x-csharp": return ".cs"
    case "text/x-go": return ".go"
    case "text/x-rust": return ".rs"
    case "text/x-swift": return ".swift"
    case "text/x-ruby": return ".rb"
    case "text/x-php": return ".php"
    default:
      // Try to infer from MIME type structure
      if mimeType.starts(with: "text/") {
        return ".txt"
      }
      return ""
    }
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
      let fileExtension = fileExtension(for: textContent.mimeType)
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
      let fileExtension = fileExtension(for: blobContent.mimeType)
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
          let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
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
