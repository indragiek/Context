// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ConnectionErrorBanner: View {
  let errors: [ConnectionError]
  let onDismiss: () -> Void

  @State private var showingErrorDetails = false
  @State private var isHovering = false
  @State private var isPressed = false

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

      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.secondary)
          .font(.system(size: 16))
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(
      Color(NSColor.controlBackgroundColor)
        .brightness(isPressed ? -0.15 : (isHovering ? -0.05 : 0))
    )
    .overlay(
      Rectangle()
        .fill(Color(NSColor.separatorColor))
        .frame(height: 1),
      alignment: .bottom
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovering = hovering
    }
    .onTapGesture {
      withAnimation(.easeInOut(duration: 0.1)) {
        isPressed = true
      }
      
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(.easeInOut(duration: 0.1)) {
          isPressed = false
        }
        showingErrorDetails = true
      }
    }
    .animation(.easeInOut(duration: 0.15), value: isHovering)
    .animation(.easeInOut(duration: 0.1), value: isPressed)
    .sheet(isPresented: $showingErrorDetails) {
      ConnectionErrorDetailView(errors: errors)
    }
  }
}
