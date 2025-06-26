// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct PropertyRow: View {
  let label: String
  let value: String
  let icon: String
  let isMonospaced: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(width: 16)

        Text(label)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(.secondary)
      }
      .frame(width: 100, alignment: .leading)

      Text(value)
        .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
        .textSelection(.enabled)
        .foregroundColor(.primary)
    }
  }
}
