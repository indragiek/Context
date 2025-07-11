// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import QuickLook
import SwiftUI

struct ResourceToolbar: View {
  let resource: EmbeddedResource
  let shareURL: URL?
  @Binding var quickLookURL: URL?
  let viewMode: ResourceViewMode
  let rawJSON: String?
  let onCopyAction: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(ResourceOperations.resourceTitle(for: resource))
        .font(.headline)
        .foregroundColor(.primary)

      Spacer()

      // Copy button - behavior changes based on view mode and resource type
      CopyButton {
        onCopyAction()
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
}
