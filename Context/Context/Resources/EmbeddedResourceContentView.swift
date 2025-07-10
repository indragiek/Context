// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import QuickLook
import SwiftUI

struct EmbeddedResourceContentView: View {
  let resource: EmbeddedResource
  @State private var shareURL: URL?
  @State private var quickLookURL: URL?

  var body: some View {
    VStack(spacing: 0) {
      ResourceToolbar(
        resource: resource,
        shareURL: shareURL,
        quickLookURL: $quickLookURL,
        viewMode: .preview,
        rawJSON: nil,
        onCopyAction: {
          ResourceOperations.copyToClipboard(resource)
        }
      )

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
    shareURL = ResourceOperations.createShareURL(for: resource)
  }
}
