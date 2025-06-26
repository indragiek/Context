// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Quartz
import QuickLook
import SwiftUI

struct QuickLookPreview: NSViewRepresentable {
  let url: URL

  func makeNSView(context: NSViewRepresentableContext<QuickLookPreview>) -> QLPreviewView {
    let preview = QLPreviewView(frame: .zero, style: .compact)!
    preview.shouldCloseWithWindow = false
    preview.autostarts = true
    return preview
  }

  func updateNSView(_ nsView: QLPreviewView, context: NSViewRepresentableContext<QuickLookPreview>)
  {
    nsView.previewItem = url as any QLPreviewItem
  }
}

// Helper to create temporary files for preview
extension QuickLookPreview {
  static func createTemporaryURL(for resource: EmbeddedResource) -> URL? {
    let tempDir = FileManager.default.temporaryDirectory
    let fileName: String
    let data: Data?

    switch resource {
    case .text(let textContent):
      // Create filename with appropriate extension based on MIME type
      let ext = fileExtension(for: textContent.mimeType)
      fileName = "preview_\(UUID().uuidString)\(ext)"
      data = textContent.text.data(using: .utf8)

    case .blob(let blobContent):
      let ext = fileExtension(for: blobContent.mimeType)
      fileName = "preview_\(UUID().uuidString)\(ext)"
      data = blobContent.blob
    }

    guard let data = data else {
      print("QuickLookPreview: No data available for resource")
      return nil
    }

    let url = tempDir.appendingPathComponent(fileName)

    do {
      try data.write(to: url)
      print("QuickLookPreview: Created temp file at \(url.path)")
      return url
    } catch {
      print("QuickLookPreview: Failed to create temporary file: \(error)")
      return nil
    }
  }

  private static func fileExtension(for mimeType: String?) -> String {
    let ext = FileExtensionHelper.fileExtension(for: mimeType)
    return ext.isEmpty ? ".txt" : ext
  }
}
