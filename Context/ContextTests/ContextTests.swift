// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI
import Testing

@testable import Context

struct JSONSyntaxHighlighterTests {
  @Test func tenThousandElementArrayHasBoundedLinearWork() {
    assertLinearWork(elementCount: 10_000)
  }

  @Test func twentyThousandElementArrayHasBoundedLinearWork() {
    assertLinearWork(elementCount: 20_000)
  }

  @Test func classifiesNestedJSONAndAllScalarFormsInSourceOrder() {
    let input = #"""
      {
        "message": "true 123 null \"quoted\" \\ slash",
        "integer": 0,
        "negative": -42,
        "fraction": 3.1415,
        "exponents": [6e10, -2.5E-3],
        "yes": true,
        "no": false,
        "none": null,
        "nested": [{"unicode": "café 👩🏽‍💻"}]
      }
      """#

    let result = highlight(input)

    #expect(String(result.attributedString.characters) == input)
    #expect(result.tokens.map(\.type) == [
      .key, .string,
      .key, .number,
      .key, .number,
      .key, .number,
      .key, .number, .number,
      .key, .boolean,
      .key, .boolean,
      .key, .null,
      .key,
      .key, .string,
    ])
    #expect(result.tokens.map { String(input[$0.range]) } == [
      "\"message\"", "\"true 123 null \\\"quoted\\\" \\\\ slash\"",
      "\"integer\"", "0",
      "\"negative\"", "-42",
      "\"fraction\"", "3.1415",
      "\"exponents\"", "6e10", "-2.5E-3",
      "\"yes\"", "true",
      "\"no\"", "false",
      "\"none\"", "null",
      "\"nested\"",
      "\"unicode\"", "\"café 👩🏽‍💻\"",
    ])
    assertOrderedOriginalRanges(result.tokens, in: input)
  }

  @Test func emitsScalarBeforeAKeyThatAppearsLater() {
    let input = #"[1, {"key": 2}]"#
    let result = highlight(input)

    #expect(result.tokens.map(\.type) == [.number, .key, .number])
    #expect(result.tokens.map { String(input[$0.range]) } == ["1", "\"key\"", "2"])
    #expect(String(result.attributedString.characters) == input)
    assertOrderedOriginalRanges(result.tokens, in: input)
  }

  @Test func retainsBaseForegroundOnWhitespaceAndPunctuation() throws {
    let input = "{ \n  \"key\" : 1 }"
    let result = highlight(input)
    let openingBrace = input.startIndex
    let whitespace = input.index(after: openingBrace)
    let key = try #require(input.range(of: "\"key\""))
    let number = try #require(input.range(of: "1"))

    #expect(foregroundColor(at: openingBrace, in: result.attributedString, text: input)
      == JSONSyntaxHighlighter.lightScheme.text)
    #expect(foregroundColor(at: whitespace, in: result.attributedString, text: input)
      == JSONSyntaxHighlighter.lightScheme.text)
    #expect(foregroundColor(in: key, attributedString: result.attributedString)
      == JSONSyntaxHighlighter.lightScheme.key)
    #expect(foregroundColor(in: number, attributedString: result.attributedString)
      == JSONSyntaxHighlighter.lightScheme.number)
  }

  @Test func searchOverlayIsCaseInsensitiveAndPreservesSyntaxForeground() throws {
    let input = #"{"Key": "VaLuE value"}"#
    let syntax = highlight(input).attributedString
    let searched = JSONSyntaxHighlighter.applySearchHighlighting(
      to: syntax, searchText: "vAlUe")
    let matches = JSONSyntaxHighlighter.findSearchMatches(in: input, searchText: "vAlUe")

    #expect(matches.count == 2)
    #expect(matches.map { String(input[$0]) } == ["VaLuE", "value"])
    #expect(String(searched.characters) == input)

    for range in matches {
      let syntaxForeground = foregroundColor(in: range, attributedString: syntax)
      #expect(syntaxForeground != nil)
      #expect(foregroundColor(in: range, attributedString: searched) == syntaxForeground)
      #expect(backgroundColor(in: range, attributedString: searched) != nil)
    }

    let keyRange = try #require(input.range(of: "\"Key\""))
    #expect(backgroundColor(in: keyRange, attributedString: searched) == nil)
  }

  @Test func malformedAndTruncatedInputsTerminateAndPreserveText() {
    let inputs = [
      "{",
      #"{"key": "unterminated"#,
      #"["trailing escape\"#,
      #"[true, fals, null, -1.2e"#,
      #"{"a": 1, "b" 2, garbage}"#,
    ]

    for input in inputs {
      var metrics = JSONSyntaxHighlighter.WorkMetrics()
      let result = JSONSyntaxHighlighter.highlightToAttributedString(
        input,
        colorScheme: JSONSyntaxHighlighter.lightScheme,
        workMetrics: &metrics
      )

      #expect(String(result.attributedString.characters) == input)
      #expect(metrics.elementReads <= input.utf8.count)
      #expect(metrics.indexAdvances <= input.utf8.count)
      #expect(metrics.syntaxForegroundMutations <= result.tokens.count + 1)
      assertOrderedOriginalRanges(result.tokens, in: input)
    }
  }

  private func assertLinearWork(elementCount: Int) {
    let input = "[" + Array(repeating: "0", count: elementCount).joined(separator: ",") + "]"
    var metrics = JSONSyntaxHighlighter.WorkMetrics()
    let result = JSONSyntaxHighlighter.highlightToAttributedString(
      input,
      colorScheme: JSONSyntaxHighlighter.lightScheme,
      workMetrics: &metrics
    )
    let workLimit = 3 * input.utf8.count + 16

    #expect(String(result.attributedString.characters) == input)
    #expect(result.tokens.count == elementCount)
    #expect(result.tokens.allSatisfy { $0.type == .number })
    #expect(result.tokens.allSatisfy { input[$0.range] == "0" })
    #expect(metrics.elementReads == input.utf8.count)
    #expect(metrics.indexAdvances == input.utf8.count)
    #expect(metrics.elementReads <= workLimit)
    #expect(metrics.indexAdvances <= workLimit)
    #expect(metrics.syntaxForegroundMutations == result.tokens.count + 1)
    assertOrderedOriginalRanges(result.tokens, in: input)
  }

  private func highlight(_ input: String) -> JSONSyntaxHighlighter.HighlightResult {
    var metrics = JSONSyntaxHighlighter.WorkMetrics()
    return JSONSyntaxHighlighter.highlightToAttributedString(
      input,
      colorScheme: JSONSyntaxHighlighter.lightScheme,
      workMetrics: &metrics
    )
  }

  private func assertOrderedOriginalRanges(
    _ tokens: [JSONSyntaxHighlighter.Token], in input: String
  ) {
    var previousEnd = input.startIndex

    for token in tokens {
      #expect(token.range.lowerBound >= previousEnd)
      #expect(token.range.lowerBound >= input.startIndex)
      #expect(token.range.upperBound <= input.endIndex)
      #expect(token.range.lowerBound < token.range.upperBound)
      previousEnd = token.range.upperBound
    }
  }

  private func foregroundColor(
    at index: String.Index,
    in attributedString: AttributedString,
    text: String
  ) -> Color? {
    let upperBound = text.index(after: index)
    return foregroundColor(in: index..<upperBound, attributedString: attributedString)
  }

  private func foregroundColor(
    in range: Range<String.Index>, attributedString: AttributedString
  ) -> Color? {
    guard
      let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
      let upperBound = AttributedString.Index(range.upperBound, within: attributedString)
    else {
      return nil
    }
    return attributedString[lowerBound..<upperBound].foregroundColor
  }

  private func backgroundColor(
    in range: Range<String.Index>, attributedString: AttributedString
  ) -> Color? {
    guard
      let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
      let upperBound = AttributedString.Index(range.upperBound, within: attributedString)
    else {
      return nil
    }
    return attributedString[lowerBound..<upperBound].backgroundColor
  }
}
