// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import ContextCore
import UniformTypeIdentifiers
import os

struct ResourceOperations {
  private static let logger = Logger(subsystem: "com.indragie.Context", category: "ResourceOperations")

  // MARK: - Title Generation

  static func resourceTitle(for resource: EmbeddedResource) -> String {
    switch resource {
    case .text(let content):
      return URL(string: content.uri)?.lastPathComponent ?? content.uri
    case .blob(let content):
      return URL(string: content.uri)?.lastPathComponent ?? content.uri
    }
  }

  // MARK: - Clipboard Operations

  static func copyToClipboard(_ resource: EmbeddedResource) {
    switch resource {
    case .text(let textContent):
      copyTextToClipboard(textContent.text)
    case .blob(let blobContent):
      if let mimeType = blobContent.mimeType, mimeType.starts(with: "image/") {
        copyImageToClipboard(blobContent.blob)
      }
    }
  }

  static func copyTextToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  static func copyImageToClipboard(_ data: Data) {
    if let image = NSImage(data: data) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([image])
    }
  }

  // MARK: - Share URL Creation

  static func createShareURL(for resource: EmbeddedResource) -> URL? {
    switch resource {
    case .text(let textContent):
      return createShareURLForText(textContent)
    case .blob(let blobContent):
      return createShareURLForBlob(blobContent)
    }
  }

  private static func createShareURLForText(_ textContent: TextResourceContents) -> URL? {
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
      return tempURL
    } catch {
      logger.error("Failed to create share URL for text: \(error)")
      return nil
    }
  }

  private static func createShareURLForBlob(_ blobContent: BlobResourceContents) -> URL? {
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
      return tempURL
    } catch {
      logger.error("Failed to create share URL: \(error)")
      return nil
    }
  }

  // MARK: - Save Operations

  @MainActor
  static func saveResource(_ resource: EmbeddedResource) {
    let savePanel = NSSavePanel()

    // Configure save panel based on resource type
    switch resource {
    case .text(let textContent):
      let fileName = URL(string: textContent.uri)?.lastPathComponent ?? "resource"
      let fileExtension = FileExtensionHelper.fileExtension(for: textContent.mimeType)
      savePanel.nameFieldStringValue =
        fileName.contains(".") ? fileName : "\(fileName)\(fileExtension)"
      savePanel.allowedContentTypes = FileExtensionHelper.allowedContentTypes(
        for: textContent.mimeType)

    case .blob(let blobContent):
      let fileName = URL(string: blobContent.uri)?.lastPathComponent ?? "resource"
      let fileExtension = FileExtensionHelper.fileExtension(for: blobContent.mimeType)
      savePanel.nameFieldStringValue =
        fileName.contains(".") ? fileName : "\(fileName)\(fileExtension)"
      savePanel.allowedContentTypes = FileExtensionHelper.allowedContentTypes(
        for: blobContent.mimeType)
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
          logger.error("Failed to save resource: \(error)")
        }
      }
    }
  }
}
