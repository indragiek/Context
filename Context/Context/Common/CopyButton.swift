// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct CopyButton: View {
  let action: () -> Void
  @State private var showCopiedIndicator = false
  @State private var copiedIndicatorTask: Task<Void, Never>?
  
  var body: some View {
    Button(action: {
      action()
      displayCopiedIndicator()
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