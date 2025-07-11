// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// A utility for common JSON encoding operations
struct JSONUtility {

  /// Encodes a value to a pretty-printed JSON string
  /// - Parameters:
  ///   - value: The value to encode
  ///   - escapeSlashes: Whether to escape forward slashes in the output (default: false)
  /// - Returns: A pretty-printed JSON string, or nil if encoding fails
  static func prettyString<T: Encodable>(from value: T, escapeSlashes: Bool = false) -> String? {
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

  /// Encodes a value to pretty-printed JSON data
  /// - Parameters:
  ///   - value: The value to encode
  ///   - escapeSlashes: Whether to escape forward slashes in the output (default: false)
  /// - Returns: Pretty-printed JSON data
  /// - Throws: EncodingError if encoding fails
  static func prettyData<T: Encodable>(from value: T, escapeSlashes: Bool = false) throws -> Data {
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
  static func compactData<T: Encodable>(from value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
  }

  /// Encodes a value to JSON data with ISO8601 date formatting (for keychain storage)
  /// - Parameter value: The value to encode
  /// - Returns: JSON data with ISO8601 date formatting
  /// - Throws: EncodingError if encoding fails
  static func keychainData<T: Encodable>(from value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
  }
}
