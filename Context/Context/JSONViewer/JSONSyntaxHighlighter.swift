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

  enum TokenType: Equatable {
    case string
    case number
    case boolean
    case null
    case key
  }

  struct Token {
    let type: TokenType
    let range: Range<String.Index>
  }

  struct WorkMetrics: Equatable {
    var elementReads = 0
    var indexAdvances = 0
    var syntaxForegroundMutations = 0
  }

  struct HighlightResult {
    let attributedString: AttributedString
    let tokens: [Token]
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
    var workMetrics = WorkMetrics()
    return highlightToAttributedString(
      text, colorScheme: colorScheme, workMetrics: &workMetrics
    ).attributedString
  }

  /// The instrumented entry point used by production and by deterministic work tests.
  /// Element reads and index advances are counted by the collection traversed by the lexer;
  /// foreground mutations are counted where attributes are applied below.
  static func highlightToAttributedString(
    _ text: String,
    colorScheme: ColorScheme,
    workMetrics: inout WorkMetrics
  ) -> HighlightResult {
    let counter = WorkCounter()
    var lexer = JSONLexer(text: text, counter: counter)
    let tokens = lexer.tokens()

    workMetrics.elementReads += counter.elementReads
    workMetrics.indexAdvances += counter.indexAdvances

    var attributedString = AttributedString(text)
    attributedString.foregroundColor = colorScheme.text
    workMetrics.syntaxForegroundMutations += 1

    for token in tokens {
      guard
        let lowerBound = AttributedString.Index(token.range.lowerBound, within: attributedString),
        let upperBound = AttributedString.Index(token.range.upperBound, within: attributedString)
      else {
        continue
      }

      attributedString[lowerBound..<upperBound].foregroundColor =
        colorForTokenType(token.type, colorScheme: colorScheme)
      workMetrics.syntaxForegroundMutations += 1
    }

    return HighlightResult(attributedString: attributedString, tokens: tokens)
  }

  static func applySearchHighlighting(to attributedString: AttributedString, searchText: String)
    -> AttributedString
  {
    guard !searchText.isEmpty else { return attributedString }

    var result = attributedString
    let text = String(attributedString.characters)

    for range in findSearchMatches(in: text, searchText: searchText) {
      if let lowerBound = AttributedString.Index(range.lowerBound, within: result),
        let upperBound = AttributedString.Index(range.upperBound, within: result)
      {
        result[lowerBound..<upperBound].backgroundColor = .yellow.opacity(0.6)
      }
    }

    return result
  }

  static func findSearchMatches(in text: String, searchText: String) -> [Range<String.Index>] {
    guard !searchText.isEmpty else { return [] }

    var matchRanges: [Range<String.Index>] = []
    var searchStartIndex = text.startIndex

    while searchStartIndex < text.endIndex {
      if let range = text.range(
        of: searchText,
        options: .caseInsensitive,
        range: searchStartIndex..<text.endIndex
      ) {
        matchRanges.append(range)
        searchStartIndex = range.upperBound
      } else {
        break
      }
    }

    return matchRanges
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

/// A collection wrapper that records every element access and forward index step. The JSON lexer
/// only retains its current index and can therefore make progress without suffix construction,
/// backward traversal, or restarting a search from a later position.
private struct CountingCollection<Base: Collection>: Collection where Base.Element == UInt8 {
  typealias Index = Base.Index

  private let base: Base
  private let counter: WorkCounter

  init(_ base: Base, counter: WorkCounter) {
    self.base = base
    self.counter = counter
  }

  var startIndex: Index { base.startIndex }
  var endIndex: Index { base.endIndex }

  subscript(position: Index) -> UInt8 {
    counter.elementReads += 1
    return base[position]
  }

  func index(after index: Index) -> Index {
    counter.indexAdvances += 1
    return base.index(after: index)
  }
}

private final class WorkCounter {
  var elementReads = 0
  var indexAdvances = 0
}

private struct JSONLexer {
  private typealias Bytes = CountingCollection<String.UTF8View>

  private static let trueBytes = Array("true".utf8)
  private static let falseBytes = Array("false".utf8)
  private static let nullBytes = Array("null".utf8)

  private let bytes: Bytes
  private var index: Bytes.Index
  private var bufferedByte: UInt8?

  init(text: String, counter: WorkCounter) {
    let bytes = CountingCollection(text.utf8, counter: counter)
    self.bytes = bytes
    self.index = bytes.startIndex
    self.bufferedByte = nil
  }

  mutating func tokens() -> [JSONSyntaxHighlighter.Token] {
    var result: [JSONSyntaxHighlighter.Token] = []

    while let byte = currentByte {
      switch byte {
      case Self.quote:
        result.append(scanString())
      case Self.minus, Self.zero...Self.nine:
        if let token = scanNumber() {
          result.append(token)
        }
      case Self.lowercaseT:
        if let token = scanLiteral(Self.trueBytes, type: .boolean) {
          result.append(token)
        }
      case Self.lowercaseF:
        if let token = scanLiteral(Self.falseBytes, type: .boolean) {
          result.append(token)
        }
      case Self.lowercaseN:
        if let token = scanLiteral(Self.nullBytes, type: .null) {
          result.append(token)
        }
      default:
        advance()
      }
    }

    return result
  }

  private var currentByte: UInt8? {
    mutating get {
      guard index != bytes.endIndex else { return nil }
      if let bufferedByte {
        return bufferedByte
      }

      let byte = bytes[index]
      bufferedByte = byte
      return byte
    }
  }

  private mutating func advance() {
    guard index != bytes.endIndex else { return }
    index = bytes.index(after: index)
    bufferedByte = nil
  }

  private mutating func scanString() -> JSONSyntaxHighlighter.Token {
    let start = index
    advance()  // Opening quote.
    var foundClosingQuote = false

    stringContents: while let byte = currentByte {
      switch byte {
      case Self.quote:
        advance()
        foundClosingQuote = true
        break stringContents
      case Self.backslash:
        advance()
        // The escaped byte cannot terminate the string. This is intentionally tolerant of
        // incomplete or invalid escape sequences so malformed input always makes progress.
        if index != bytes.endIndex {
          advance()
        }
      default:
        advance()
      }
    }

    let end = index
    var type = JSONSyntaxHighlighter.TokenType.string

    if foundClosingQuote {
      skipWhitespace()
      if currentByte == Self.colon {
        type = .key
      }
    }

    return JSONSyntaxHighlighter.Token(type: type, range: start..<end)
  }

  private mutating func scanNumber() -> JSONSyntaxHighlighter.Token? {
    let start = index

    if currentByte == Self.minus {
      advance()
      guard let byte = currentByte, Self.isDigit(byte) else {
        return nil
      }
    }

    if currentByte == Self.zero {
      advance()
      // Continue through digits in malformed leading-zero numbers rather than emitting
      // overlapping or adjacent number tokens.
      while let byte = currentByte, Self.isDigit(byte) {
        advance()
      }
    } else {
      guard let byte = currentByte, Self.isDigit(byte) else {
        return nil
      }
      while let byte = currentByte, Self.isDigit(byte) {
        advance()
      }
    }

    if currentByte == Self.period {
      advance()
      while let byte = currentByte, Self.isDigit(byte) {
        advance()
      }
    }

    if let byte = currentByte, byte == Self.lowercaseE || byte == Self.uppercaseE {
      advance()
      if let sign = currentByte, sign == Self.plus || sign == Self.minus {
        advance()
      }
      while let digit = currentByte, Self.isDigit(digit) {
        advance()
      }
    }

    return JSONSyntaxHighlighter.Token(type: .number, range: start..<index)
  }

  private mutating func scanLiteral(
    _ literal: [UInt8], type: JSONSyntaxHighlighter.TokenType
  ) -> JSONSyntaxHighlighter.Token? {
    let start = index

    for expectedByte in literal {
      guard currentByte == expectedByte else {
        return nil
      }
      advance()
    }

    guard Self.isLiteralBoundary(currentByte) else {
      return nil
    }

    return JSONSyntaxHighlighter.Token(type: type, range: start..<index)
  }

  private mutating func skipWhitespace() {
    while let byte = currentByte, Self.isWhitespace(byte) {
      advance()
    }
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    byte >= zero && byte <= nine
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == space || byte == tab || byte == lineFeed || byte == carriageReturn
  }

  private static func isLiteralBoundary(_ byte: UInt8?) -> Bool {
    guard let byte else { return true }
    return !isDigit(byte)
      && !(byte >= uppercaseA && byte <= uppercaseZ)
      && !(byte >= lowercaseA && byte <= lowercaseZ)
      && byte != underscore
  }

  private static let quote = UInt8(ascii: "\"")
  private static let backslash = UInt8(ascii: "\\")
  private static let colon = UInt8(ascii: ":")
  private static let minus = UInt8(ascii: "-")
  private static let plus = UInt8(ascii: "+")
  private static let period = UInt8(ascii: ".")
  private static let zero = UInt8(ascii: "0")
  private static let nine = UInt8(ascii: "9")
  private static let lowercaseE = UInt8(ascii: "e")
  private static let uppercaseE = UInt8(ascii: "E")
  private static let lowercaseT = UInt8(ascii: "t")
  private static let lowercaseF = UInt8(ascii: "f")
  private static let lowercaseN = UInt8(ascii: "n")
  private static let uppercaseA = UInt8(ascii: "A")
  private static let uppercaseZ = UInt8(ascii: "Z")
  private static let lowercaseA = UInt8(ascii: "a")
  private static let lowercaseZ = UInt8(ascii: "z")
  private static let underscore = UInt8(ascii: "_")
  private static let space = UInt8(ascii: " ")
  private static let tab = UInt8(ascii: "\t")
  private static let lineFeed = UInt8(ascii: "\n")
  private static let carriageReturn = UInt8(ascii: "\r")
}
