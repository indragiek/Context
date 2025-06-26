// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct ConnectionStateIcon: View {
  let state: Client.ConnectionState
  let isSelected: Bool
  let onReload: (() -> Void)?

  @State private var isHovering = false

  var body: some View {
    Group {
      if isHovering && onReload != nil {
        Button(action: { onReload?() }) {
          Image(systemName: "arrow.clockwise.circle.fill")
            .foregroundStyle(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
      } else {
        switch state {
        case .connecting:
          Image(systemName: "clock.circle.fill")
            .foregroundStyle(isSelected ? .white : .orange)
        case .connected:
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(isSelected ? .white : .green)
        case .disconnected:
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(isSelected ? .white : .red)
        case .disconnecting:
          Image(systemName: "clock.circle.fill")
            .foregroundStyle(isSelected ? .white : .orange)
        }
      }
    }
    .onHover { hovering in
      isHovering = hovering
    }
  }
}
