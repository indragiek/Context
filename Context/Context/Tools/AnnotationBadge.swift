// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct AnnotationBadge: View {
  let label: String
  let color: Color
  let icon: String

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.caption2)

      Text(label)
        .font(.caption2)
        .fontWeight(.medium)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(color.opacity(0.2))
    )
    .foregroundColor(color)
  }
}
