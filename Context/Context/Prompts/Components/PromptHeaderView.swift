// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct PromptHeaderView: View {
  let prompt: Prompt
  @Binding var showingFullDescription: Bool
  
  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(prompt.name)
          .font(.title2)
          .fontWeight(.semibold)
        
        if let description = prompt.description {
          VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(description))
              .font(.callout)
              .foregroundColor(.secondary)
              .textSelection(.enabled)
              .lineLimit(3)
            
            showMoreButton
          }
        } else {
          showMoreButton
        }
      }
      
      Spacer()
    }
  }
  
  private var showMoreButton: some View {
    Button(action: {
      showingFullDescription = true
    }) {
      Text("Show more")
        .font(.caption)
        .foregroundColor(.accentColor)
    }
    .buttonStyle(.plain)
  }
}
