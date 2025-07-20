// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// A utility for common JSON encoding operations
public struct JSONUtility {

  /// Encodes a value to a pretty-printed JSON string
  /// - Parameters:
  ///   - value: The value to encode
  ///   - escapeSlashes: Whether to escape forward slashes in the output (default: false)
  /// - Returns: A pretty-printed JSON string, or nil if encoding fails
  public static func prettyString<T: Encodable>(from value: T, escapeSlashes: Bool = false) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting =
      escapeSlashes
      ? [.prettyPrinted, .sortedKeys]
      : [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    guard let data = try? encoder.encode(value),
      let string = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return string
  }

  /// Encodes a value to a compact JSON string (without pretty printing)
  /// - Parameters:
  ///   - value: The value to encode
  ///   - escapeSlashes: Whether to escape forward slashes in the output (default: false)
  /// - Returns: A compact JSON string, or nil if encoding fails
  public static func compactString<T: Encodable>(from value: T, escapeSlashes: Bool = false) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting =
      escapeSlashes
      ? [.sortedKeys]
      : [.sortedKeys, .withoutEscapingSlashes]

    guard let data = try? encoder.encode(value),
      let string = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return string
  }

  /// Encodes a value to pretty-printed JSON data
  /// - Parameters:
  ///   - value: The value to encode
  ///   - escapeSlashes: Whether to escape forward slashes in the output (default: false)
  /// - Returns: Pretty-printed JSON data
  /// - Throws: EncodingError if encoding fails
  public static func prettyData<T: Encodable>(from value: T, escapeSlashes: Bool = false) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting =
      escapeSlashes
      ? [.prettyPrinted, .sortedKeys]
      : [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    return try encoder.encode(value)
  }

  /// Encodes a value to compact JSON data (for storage/transmission)
  /// - Parameter value: The value to encode
  /// - Returns: Compact JSON data with sorted keys
  /// - Throws: EncodingError if encoding fails
  public static func compactData<T: Encodable>(from value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
  }

  /// Encodes a value to JSON data with ISO8601 date formatting (for keychain storage)
  /// - Parameter value: The value to encode
  /// - Returns: JSON data with ISO8601 date formatting
  /// - Throws: EncodingError if encoding fails
  public static func keychainData<T: Encodable>(from value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
  }

  /// Checks if a string is likely JSON by examining its structure
  /// - Parameter string: The string to check
  /// - Returns: true if the string appears to be JSON (starts with { or [ and ends with } or ])
  public static func isLikelyJSON(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
      || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
  }

  /// Attempts to extract a JSONValue from the beginning or end of a string
  /// - Parameter string: The string to extract JSON from
  /// - Returns: A JSONValue if valid JSON is found at the beginning or end of the string, nil otherwise
  public static func extractJSON(from string: String) -> JSONValue? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    
    // Check if string starts with JSON
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
      if let result = extractJSONFromStart(of: trimmed) {
        return result.jsonValue
      }
    }
    
    // Check if string ends with JSON
    if trimmed.hasSuffix("}") || trimmed.hasSuffix("]") {
      if let result = extractJSONFromEnd(of: trimmed) {
        return result.jsonValue
      }
    }
    
    return nil
  }

  /// Extracts JSON starting from the beginning of a string by finding matching brackets
  private static func extractJSONFromStart(of string: String) -> (jsonValue: JSONValue, endIndex: String.Index)? {
    var bracketCount = 0
    var inString = false
    var escaped = false
    var endIndex: String.Index?
    
    for (index, char) in string.enumerated() {
      if !escaped && char == "\"" {
        inString.toggle()
      } else if !inString {
        if char == "{" || char == "[" {
          bracketCount += 1
        } else if char == "}" || char == "]" {
          bracketCount -= 1
          if bracketCount == 0 {
            endIndex = string.index(string.startIndex, offsetBy: index + 1)
            break
          }
        }
      }
      escaped = !escaped && char == "\\"
    }
    
    if let endIndex = endIndex {
      let jsonString = String(string[..<endIndex])
      if let jsonValue = parseJSON(jsonString) {
        return (jsonValue, endIndex)
      }
    }
    
    return nil
  }

  /// Extracts JSON ending at the end of a string by finding matching brackets in reverse
  private static func extractJSONFromEnd(of string: String) -> (jsonValue: JSONValue, startIndex: String.Index)? {
    var bracketCount = 0
    var inString = false
    var startIndex: String.Index?
    
    // Process string in reverse
    var i = string.index(before: string.endIndex)
    while i >= string.startIndex {
      let char = string[i]
      
      // Check if we're in a string (accounting for escapes)
      if char == "\"" {
        // Check if this quote is escaped
        var escapeCount = 0
        var j = string.index(before: i)
        while j >= string.startIndex && string[j] == "\\" {
          escapeCount += 1
          if j > string.startIndex {
            j = string.index(before: j)
          } else {
            break
          }
        }
        if escapeCount % 2 == 0 {
          inString.toggle()
        }
      } else if !inString {
        if char == "}" || char == "]" {
          bracketCount += 1
        } else if char == "{" || char == "[" {
          bracketCount -= 1
          if bracketCount == 0 {
            startIndex = i
            break
          }
        }
      }
      
      if i > string.startIndex {
        i = string.index(before: i)
      } else {
        break
      }
    }
    
    if let startIndex = startIndex {
      let jsonString = String(string[startIndex...])
      if let jsonValue = parseJSON(jsonString) {
        return (jsonValue, startIndex)
      }
    }
    
    return nil
  }

  /// Parses a JSON string into a JSONValue
  private static func parseJSON(_ string: String) -> JSONValue? {
    guard let data = string.data(using: .utf8),
          let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data) else {
      return nil
    }
    return jsonValue
  }

  /// Extracts both cleaned text and any JSONValue from a string in a single pass
  /// - Parameter string: The string to process
  /// - Returns: A tuple containing the text with JSON removed and an optional JSONValue if found
  private static func extractTextAndJSON(from string: String) -> (text: String, json: JSONValue?) {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Check if the string starts with JSON
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
      if let result = extractJSONFromStart(of: trimmed) {
        let afterJSON = String(trimmed[result.endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !afterJSON.isEmpty {
          return (afterJSON, result.jsonValue)
        }
        // If there's no text after JSON, return original string with JSON
        return (string, result.jsonValue)
      }
    }
    
    // Check if the string ends with JSON
    if trimmed.hasSuffix("}") || trimmed.hasSuffix("]") {
      if let result = extractJSONFromEnd(of: trimmed) {
        let beforeJSON = String(trimmed[..<result.startIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !beforeJSON.isEmpty {
          return (beforeJSON, result.jsonValue)
        }
        // If there's no text before JSON, return original string with JSON
        return (string, result.jsonValue)
      }
    }
    
    // No JSON found
    return (string, nil)
  }

  /// Gets the raw error description from an error, preferring errorDescription if available
  private static func getRawErrorDescription(from error: any Error) -> String {
    if let localizedError = error as? LocalizedError,
       let errorDescription = localizedError.errorDescription {
      return errorDescription
    } else {
      return error.localizedDescription
    }
  }

  /// Prepares content for clipboard from JSON response or error
  /// - Parameters:
  ///   - json: Optional JSONValue to convert to string
  ///   - error: Optional error to extract content from
  /// - Returns: A string suitable for clipboard copying
  public static func clipboardContents(json: JSONValue?, error: (any Error)?) -> String {
    // Prefer JSON response if available
    if let jsonValue = json {
      return prettyString(from: jsonValue) ?? "Failed to encode JSON"
    }
    
    // If no JSON response, extract from error
    if let error = error {
      let (_, extractedJSON) = extractErrorAndJSON(from: error)
      
      // Try to pretty-print extracted JSON
      if let jsonValue = extractedJSON,
         let prettyJSON = prettyString(from: jsonValue) {
        return prettyJSON
      }
      
      // Return raw error text if no JSON found
      return getRawErrorDescription(from: error)
    }
    
    return ""
  }

  /// Gets the error description from an error, preferring errorDescription if available
  /// This function also strips any JSON payload from the beginning or end of the error text
  public static func getErrorDescription(from error: any Error) -> String {
    let (cleanedText, _) = extractErrorAndJSON(from: error)
    return cleanedText
  }

  /// Attempts to extract a JSONValue from an error's description
  /// - Parameter error: The error to extract JSON from
  /// - Returns: A JSONValue if valid JSON is found in the error description, nil otherwise
  public static func extractJSON(from error: any Error) -> JSONValue? {
    let (_, json) = extractErrorAndJSON(from: error)
    return json
  }

  /// Extracts both the error description (with JSON stripped) and any JSONValue from an error
  /// - Parameter error: The error to process
  /// - Returns: A tuple containing the error description with JSON removed and an optional JSONValue if found
  public static func extractErrorAndJSON(from error: any Error) -> (errorDescription: String, json: JSONValue?) {
    let rawDescription = getRawErrorDescription(from: error)
    let (text, json) = extractTextAndJSON(from: rawDescription)
    return (errorDescription: text, json: json)
  }
}
