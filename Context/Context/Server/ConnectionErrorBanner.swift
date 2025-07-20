// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ConnectionErrorBanner: View {
  let errors: [ConnectionError]
  let onDismiss: () -> Void

  @State private var showingErrorDetails = false

  private var latestError: ConnectionError? {
    errors.last
  }

  var body: some View {
    HStack(spacing: 12) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
          .font(.system(size: 16))

        if errors.count > 1 {
          Text("\(errors.count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.red)
            .clipShape(Capsule())
            .offset(x: 8, y: -6)
        }
      }

      if let latestError = latestError {
        Text(latestError.errorDescription)
          .font(.system(size: 13))
          .foregroundColor(.primary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button("Show Details") {
        showingErrorDetails = true
      }
      .buttonStyle(.link)
      .font(.system(size: 12))

      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.secondary)
          .font(.system(size: 16))
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color(NSColor.controlBackgroundColor))
    .overlay(
      Rectangle()
        .fill(Color(NSColor.separatorColor))
        .frame(height: 1),
      alignment: .bottom
    )
    .sheet(isPresented: $showingErrorDetails) {
      ConnectionErrorDetailView(errors: errors)
    }
  }
}
