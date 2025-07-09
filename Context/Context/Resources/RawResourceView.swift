// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct RawResourceView: View {
  let rawJSON: String
  let error: String?
  @State private var showCopiedIndicator = false
  @State private var copiedIndicatorTask: Task<Void, Never>?
  
  var body: some View {
    VStack(spacing: 0) {
      // Toolbar
      HStack {
        Text("Raw JSON Response")
          .font(.headline)
        
        Spacer()
        
        Button(action: {
          copyToClipboard()
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
      .padding(12)
      .background(Color(NSColor.controlBackgroundColor))
      
      Divider()
      
      // JSON Content
      ScrollView {
        Text(rawJSON)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
      .background(Color(NSColor.textBackgroundColor))
    }
  }
  
  private func copyToClipboard() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(rawJSON, forType: .string)
    
    // Cancel any existing task
    copiedIndicatorTask?.cancel()
    
    // Show indicator
    withAnimation(.easeInOut(duration: 0.2)) {
      showCopiedIndicator = true
    }
    
    // Hide after delay
    copiedIndicatorTask = Task {
      try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
      if !Task.isCancelled {
        await MainActor.run {
          withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedIndicator = false
          }
        }
      }
    }
  }
}