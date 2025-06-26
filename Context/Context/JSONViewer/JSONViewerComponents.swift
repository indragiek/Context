// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

// MARK: - Line Number Ribbon

struct LineNumberRibbon: View {
  let contentLines: [String]
  let cachedWidth: CGFloat

  private var lineNumbers: String {
    (1...contentLines.count).map { "\($0)" }.joined(separator: "\n")
  }

  var body: some View {
    Text(lineNumbers)
      .font(.system(.body, design: .monospaced))
      .lineSpacing(5)
      .foregroundColor(.secondary)
      .multilineTextAlignment(.trailing)
      .frame(width: cachedWidth, alignment: .trailing)
      .padding(.top, 4)
      .padding(.bottom, 16)
      .padding(.horizontal, 8)
      .frame(width: cachedWidth + 16)
      .fixedSize(horizontal: true, vertical: false)
      .background(Color(NSColor.controlBackgroundColor))
  }
}
