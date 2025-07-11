// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct JSONSyntaxHighlighter {
  struct ColorScheme {
    let string: Color
    let number: Color
    let boolean: Color
    let null: Color
    let key: Color
    let punctuation: Color
    let text: Color
  }

  static let lightScheme = ColorScheme(
    string: Color(red: 0.77, green: 0.10, blue: 0.09),
    number: Color(red: 0.11, green: 0.00, blue: 0.81),
    boolean: Color(red: 0.64, green: 0.11, blue: 0.68),
    null: Color(red: 0.64, green: 0.11, blue: 0.68),
    key: Color(red: 0.00, green: 0.45, blue: 0.45),
    punctuation: Color.primary,
    text: Color.primary
  )

  static let darkScheme = ColorScheme(
    string: Color(red: 1.00, green: 0.33, blue: 0.33),
    number: Color(red: 0.67, green: 0.85, blue: 1.00),
    boolean: Color(red: 0.89, green: 0.67, blue: 1.00),
    null: Color(red: 0.89, green: 0.67, blue: 1.00),
    key: Color(red: 0.40, green: 0.85, blue: 0.85),
    punctuation: Color.primary,
    text: Color.primary
  )

  static func highlight(_ text: String, colorScheme: ColorScheme, searchText: String = "") -> Text {
    if searchText.isEmpty {
      let attributedString = highlightToAttributedString(text, colorScheme: colorScheme)
      return Text(attributedString)
    } else {
      var attributedString = highlightToAttributedString(text, colorScheme: colorScheme)
      attributedString = applySearchHighlighting(to: attributedString, searchText: searchText)
      return Text(attributedString)
    }
  }

  static func highlightToAttributedString(_ text: String, colorScheme: ColorScheme)
    -> AttributedString
  {
    var attributedString = AttributedString(text)

    var currentIndex = text.startIndex

    while currentIndex < text.endIndex {
      let remainingText = String(text[currentIndex...])

      if let match = findNextToken(in: remainingText) {
        let beforeMatchStartString = currentIndex
        let matchStartString = text.index(
          currentIndex,
          offsetBy: remainingText.distance(
            from: remainingText.startIndex, to: match.range.lowerBound))
        let matchEndString = text.index(
          currentIndex,
          offsetBy: remainingText.distance(
            from: remainingText.startIndex, to: match.range.upperBound))

        if let beforeMatchStartAttr = AttributedString.Index(
          beforeMatchStartString, within: attributedString),
          let matchStartAttr = AttributedString.Index(matchStartString, within: attributedString),
          let matchEndAttr = AttributedString.Index(matchEndString, within: attributedString)
        {

          if beforeMatchStartAttr < matchStartAttr {
            attributedString[beforeMatchStartAttr..<matchStartAttr].foregroundColor =
              colorScheme.text
          }

          let color = colorForTokenType(match.type, colorScheme: colorScheme)
          attributedString[matchStartAttr..<matchEndAttr].foregroundColor = color
        }

        let advanceDistance = remainingText.distance(
          from: remainingText.startIndex, to: match.range.upperBound)
        currentIndex = text.index(currentIndex, offsetBy: advanceDistance)
      } else {
        if let remainingStartAttr = AttributedString.Index(currentIndex, within: attributedString) {
          attributedString[remainingStartAttr..<attributedString.endIndex].foregroundColor =
            colorScheme.text
        }
        break
      }
    }

    return attributedString
  }

  static func applySearchHighlighting(to attributedString: AttributedString, searchText: String)
    -> AttributedString
  {
    if searchText.isEmpty {
      return attributedString
    }

    var result = attributedString
    let text = String(attributedString.characters)
    let searchLower = searchText.lowercased()
    let textLower = text.lowercased()

    var matchRanges: [Range<String.Index>] = []
    var searchStartIndex = textLower.startIndex

    while searchStartIndex < textLower.endIndex {
      if let range = textLower.range(of: searchLower, range: searchStartIndex..<textLower.endIndex)
      {
        matchRanges.append(range)
        searchStartIndex = range.upperBound
      } else {
        break
      }
    }

    for range in matchRanges {
      if let lowerBound = AttributedString.Index(range.lowerBound, within: result),
        let upperBound = AttributedString.Index(range.upperBound, within: result)
      {
        let attributedRange = lowerBound..<upperBound
        result[attributedRange].backgroundColor = .yellow.opacity(0.6)
      }
    }

    return result
  }

  static func findSearchMatches(in text: String, searchText: String) -> [Range<String.Index>] {
    guard !searchText.isEmpty else { return [] }

    let searchLower = searchText.lowercased()
    let textLower = text.lowercased()
    var matchRanges: [Range<String.Index>] = []
    var searchStartIndex = textLower.startIndex

    while searchStartIndex < textLower.endIndex {
      if let range = textLower.range(of: searchLower, range: searchStartIndex..<textLower.endIndex)
      {
        matchRanges.append(range)
        searchStartIndex = range.upperBound
      } else {
        break
      }
    }

    return matchRanges
  }

  private enum TokenType {
    case string
    case number
    case boolean
    case null
    case key
  }

  private struct TokenMatch {
    let type: TokenType
    let range: Range<String.Index>
  }

  private static func findNextToken(in text: String) -> TokenMatch? {
    let keyPattern = #""[^"\\]*(?:\\.[^"\\]*)*"\s*:"#
    if let keyRange = text.range(of: keyPattern, options: .regularExpression) {
      let matchedText = String(text[keyRange])
      if let quoteIndex = matchedText.lastIndex(of: "\"") {
        let endOffset = matchedText.distance(from: matchedText.startIndex, to: quoteIndex) + 1
        let adjustedEnd = text.index(keyRange.lowerBound, offsetBy: endOffset)
        let adjustedRange = Range(uncheckedBounds: (keyRange.lowerBound, adjustedEnd))
        return TokenMatch(type: .key, range: adjustedRange)
      }
    }

    let patterns: [(TokenType, String)] = [
      (.string, #""[^"\\]*(?:\\.[^"\\]*)*""#),
      (.number, #"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#),
      (.boolean, #"\b(?:true|false)\b"#),
      (.null, #"\bnull\b"#),
    ]

    var earliestMatch: TokenMatch?
    var earliestRange: Range<String.Index>?

    for (tokenType, pattern) in patterns {
      if let range = text.range(of: pattern, options: .regularExpression) {
        if earliestRange == nil || range.lowerBound < earliestRange!.lowerBound {
          earliestMatch = TokenMatch(type: tokenType, range: range)
          earliestRange = range
        }
      }
    }

    return earliestMatch
  }

  private static func colorForTokenType(_ type: TokenType, colorScheme: ColorScheme) -> Color {
    switch type {
    case .string: return colorScheme.string
    case .number: return colorScheme.number
    case .boolean: return colorScheme.boolean
    case .null: return colorScheme.null
    case .key: return colorScheme.key
    }
  }
}
