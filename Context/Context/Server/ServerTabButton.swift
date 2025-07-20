// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ServerTabButton: View {
  let tab: ServerTab
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(tab.rawValue)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(isSelected ? .white : .primary)
        .frame(minWidth: 60, minHeight: 24)
        .padding(.horizontal, 12)
        .background(
          Rectangle()
            .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
