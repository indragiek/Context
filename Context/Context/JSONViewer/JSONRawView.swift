// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct JSONRawView: View {
  let jsonValue: JSONValue
  let searchText: String
  let isSearchActive: Bool
  @State private var cachedLineNumberWidth: CGFloat = 0

  var body: some View {
    GeometryReader { geometry in
      ScrollView([.horizontal, .vertical]) {
        HStack(alignment: .top, spacing: 0) {
          LineNumberRibbon(
            contentLines: contentLines,
            cachedWidth: cachedLineNumberWidth
          )

          // Vertical separator
          Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .fixedSize(horizontal: true, vertical: false)

          JSONContentView(
            contentLines: contentLines,
            searchText: searchText,
            isSearchActive: isSearchActive
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.textBackgroundColor))
        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
      }
      .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
    .background(Color(NSColor.textBackgroundColor))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      calculateAndCacheLineNumberWidth()
    }
    .onChange(of: jsonValue) { _, _ in
      calculateAndCacheLineNumberWidth()
    }
  }

  private func calculateAndCacheLineNumberWidth() {
    let maxLineNumber = contentLines.count
    let maxLineString = String(maxLineNumber)

    // Use actual font metrics for precise width calculation
    let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    let textWidth = maxLineString.size(withAttributes: [.font: font]).width

    // Calculate maximum width for 5 digits (99999)
    let maxWidthString = "99999"
    let maxWidth = maxWidthString.size(withAttributes: [.font: font]).width

    // Use the smaller of actual width needed or maximum width for 5 digits
    cachedLineNumberWidth = min(textWidth, maxWidth)
  }

  private var formattedJSON: String {
    guard let jsonString = JSONUtility.prettyString(from: jsonValue) else {
      return "Unable to encode JSON"
    }

    return jsonString
  }

  private var contentLines: [String] {
    let lines = formattedJSON.components(separatedBy: .newlines)
    // Remove trailing empty lines
    var trimmedLines = lines
    while trimmedLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
      trimmedLines.removeLast()
    }
    return trimmedLines
  }

  private var lineHeight: CGFloat {
    let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    return font.boundingRectForFont.height
  }
}
