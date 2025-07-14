// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import RegexBuilder
import os

/// Validates string format constraints in JSON Schema
public struct JSONSchemaFormatValidator {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaFormatValidator")
  
  public init() {}
  
  /// Validate a string value against a format constraint
  public func validate(_ value: String, format: String) async -> Bool {
    switch format {
    case "email":
      return validateEmail(value)
    case "idn-email":
      return validateIDNEmail(value)
    case "uri", "url":
      return validateURI(value)
    case "uri-reference":
      return validateURIReference(value)
    case "iri":
      return validateIRI(value)
    case "iri-reference":
      return validateIRIReference(value)
    case "uri-template":
      return validateURITemplate(value)
    case "date":
      return validateDate(value)
    case "time":
      return validateTime(value)
    case "date-time":
      return validateDateTime(value)
    case "duration":
      return validateDuration(value)
    case "hostname":
      return validateHostname(value)
    case "idn-hostname":
      return validateIDNHostname(value)
    case "ipv4":
      return validateIPv4(value)
    case "ipv6":
      return validateIPv6(value)
    case "uuid":
      return validateUUID(value)
    case "regex":
      return await validateRegex(value)
    case "json-pointer":
      return validateJSONPointer(value)
    case "relative-json-pointer":
      return validateRelativeJSONPointer(value)
    default:
      // Unknown format - consider valid per spec
      logger.debug("Unknown format type: \(format)")
      return true
    }
  }
  
  // MARK: - Email Formats
  
  private func validateEmail(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.email) != nil
  }
  
  private func validateIDNEmail(_ value: String) -> Bool {
    // For internationalized domain names, we need to be more permissive
    // This is a simplified check that allows Unicode characters in domain
    let parts = value.split(separator: "@", maxSplits: 1)
    guard parts.count == 2 else { return false }
    
    let localPart = String(parts[0])
    let domainPart = String(parts[1])
    
    // Local part validation (simplified)
    guard !localPart.isEmpty && localPart.count <= 64 else { return false }
    
    // Domain part can contain Unicode
    guard !domainPart.isEmpty && domainPart.contains(".") else { return false }
    
    return true
  }
  
  // MARK: - URI/IRI Formats
  
  private func validateURI(_ value: String) -> Bool {
    guard let url = URL(string: value) else { return false }
    // Check for required components
    return url.scheme != nil
  }
  
  private func validateURIReference(_ value: String) -> Bool {
    // URI reference can be relative or absolute
    if URL(string: value) != nil {
      return true
    }
    // Additional checks for relative references
    return !value.isEmpty
  }
  
  private func validateIRI(_ value: String) -> Bool {
    // IRI (Internationalized Resource Identifier) validation
    // Must have a scheme and allow Unicode characters
    guard !value.isEmpty else { return false }
    
    // Check for whitespace
    guard !value.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
    
    // Check for scheme (required for IRI)
    let schemeRegex = #/^[a-zA-Z][a-zA-Z0-9+.-]*:/#
    guard value.contains(schemeRegex) else { return false }
    
    // Check for invalid characters
    let invalidChars = CharacterSet(charactersIn: "<>\"{}|\\^`")
    guard value.rangeOfCharacter(from: invalidChars) == nil else { return false }
    
    // Basic structure validation
    if let match = value.firstMatch(of: schemeRegex) {
      let schemeEnd = match.range.upperBound
      let afterScheme = String(value[schemeEnd...])
      
      // Check for authority (optional)
      if afterScheme.hasPrefix("//") {
        // Has authority section
        let authorityAndPath = String(afterScheme.dropFirst(2))
        
        // Find end of authority (first /, ?, or #)
        var pathStart = authorityAndPath.endIndex
        for (index, char) in authorityAndPath.enumerated() {
          if char == "/" || char == "?" || char == "#" {
            pathStart = authorityAndPath.index(authorityAndPath.startIndex, offsetBy: index)
            break
          }
        }
        let authority = String(authorityAndPath[..<pathStart])
        
        // Basic authority validation (can contain userinfo@host:port)
        if authority.contains("@") {
          let parts = authority.split(separator: "@", maxSplits: 1)
          if parts.count != 2 { return false }
        }
      }
    }
    
    return true
  }
  
  private func validateIRIReference(_ value: String) -> Bool {
    // IRI reference can be relative or absolute
    guard !value.isEmpty else { return false }
    
    // Check for whitespace
    guard !value.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
    
    // Check for invalid characters
    let invalidChars = CharacterSet(charactersIn: "<>\"{}|\\^`")
    guard value.rangeOfCharacter(from: invalidChars) == nil else { return false }
    
    // If it starts with a scheme, validate as full IRI
    let schemeRegex = #/^[a-zA-Z][a-zA-Z0-9+.-]*:/#
    if value.contains(schemeRegex) {
      return validateIRI(value)
    }
    
    // Otherwise it's a relative reference, which is valid
    return true
  }
  
  private func validateURITemplate(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.uriTemplate) != nil
  }
  
  // MARK: - Date/Time Formats
  
  private func validateDate(_ value: String) -> Bool {
    guard value.wholeMatch(of: JSONSchemaFormatRegexes.date) != nil else {
      return false
    }
    
    // Additional validation for valid dates
    let components = value.split(separator: "-").compactMap { Int($0) }
    guard components.count == 3 else { return false }
    
    let year = components[0]
    let month = components[1]
    let day = components[2]
    
    // Basic range checks
    guard month >= 1 && month <= 12 else { return false }
    guard day >= 1 && day <= 31 else { return false }
    
    // More precise day validation based on month
    let daysInMonth: [Int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    var maxDay = daysInMonth[month - 1]
    
    // Leap year check for February
    if month == 2 && isLeapYear(year) {
      maxDay = 29
    }
    
    return day <= maxDay
  }
  
  private func isLeapYear(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
  }
  
  private func validateTime(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.time) != nil
  }
  
  private func validateDateTime(_ value: String) -> Bool {
    // Use ISO8601DateFormatter for comprehensive validation
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    
    // Also try without fractional seconds
    if formatter.date(from: value) != nil {
      return true
    }
    
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value) != nil
  }
  
  private func validateDuration(_ value: String) -> Bool {
    // ISO 8601 duration validation
    guard value.wholeMatch(of: JSONSchemaFormatRegexes.duration) != nil else {
      return false
    }
    // Duration must have at least one component
    return value != "P" && value != "PT"
  }
  
  // MARK: - Network Formats
  
  private func validateHostname(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.hostname) != nil
  }
  
  private func validateIDNHostname(_ value: String) -> Bool {
    // Internationalized domain names can contain Unicode
    // Basic validation: not empty, has valid structure
    guard !value.isEmpty && value.count <= 253 else { return false }
    
    let labels = value.split(separator: ".")
    guard !labels.isEmpty else { return false }
    
    for label in labels {
      guard !label.isEmpty && label.count <= 63 else { return false }
      // Check that label doesn't start or end with hyphen
      if label.hasPrefix("-") || label.hasSuffix("-") {
        return false
      }
    }
    
    return true
  }
  
  private func validateIPv4(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.ipv4) != nil
  }
  
  private func validateIPv6(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.ipv6) != nil
  }
  
  // MARK: - Other Formats
  
  private func validateUUID(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.uuid) != nil
  }
  
  private func validateRegex(_ value: String) async -> Bool {
    // Check for dangerous patterns before compilation
    if await JSONSchemaRegexCache.shared.isDangerousPattern(value) {
      return false
    }
    
    // Try to compile as a regex
    do {
      _ = try Regex(value)
      return true
    } catch {
      return false
    }
  }
  
  private func validateJSONPointer(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.jsonPointer) != nil
  }
  
  private func validateRelativeJSONPointer(_ value: String) -> Bool {
    value.wholeMatch(of: JSONSchemaFormatRegexes.relativeJsonPointer) != nil
  }
}

// MARK: - Content Validation

public struct JSONSchemaContentValidator {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaContentValidator")
  
  public init() {}
  
  /// Validate encoded content
  public func validateEncodedContent(_ content: String, mediaType: String, encoding: String) -> Bool {
    guard let decodedData = decodeContent(content, encoding: encoding) else {
      return false
    }
    
    return validateMediaType(decodedData, mediaType: mediaType)
  }
  
  /// Validate raw content against media type
  public func validateMediaType(_ content: String, mediaType: String) -> Bool {
    guard let data = content.data(using: .utf8) else {
      return false
    }
    return validateMediaType(data, mediaType: mediaType)
  }
  
  private func validateMediaType(_ data: Data, mediaType: String) -> Bool {
    switch mediaType {
    case "application/json":
      return validateJSON(data)
    case "application/xml", "text/xml":
      return validateXML(data)
    case "text/plain":
      return true // Plain text is always valid
    case "text/html":
      return validateHTML(data)
    default:
      // For unknown media types, consider valid
      logger.debug("Unknown media type: \(mediaType)")
      return true
    }
  }
  
  private func decodeContent(_ content: String, encoding: String) -> Data? {
    switch encoding.lowercased() {
    case "base64":
      return Data(base64Encoded: content)
    case "base64url":
      // Convert base64url to base64
      let base64 = content
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
      let padded = base64.padding(toLength: ((base64.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
      return Data(base64Encoded: padded)
    case "binary":
      // For binary, the content should be the raw string
      return content.data(using: .utf8)
    case "quoted-printable":
      // Simplified quoted-printable decoding
      return decodeQuotedPrintable(content)
    default:
      logger.warning("Unknown content encoding: \(encoding)")
      return nil
    }
  }
  
  private func decodeQuotedPrintable(_ content: String) -> Data? {
    var result = Data()
    var index = content.startIndex
    
    while index < content.endIndex {
      if content[index] == "=" {
        let nextIndex = content.index(after: index)
        if nextIndex < content.endIndex && content[nextIndex] == "\n" {
          // Soft line break, skip
          index = content.index(after: nextIndex)
        } else if content.distance(from: nextIndex, to: content.endIndex) >= 2 {
          // Encoded byte
          let hex = String(content[nextIndex...content.index(nextIndex, offsetBy: 1)])
          if let byte = UInt8(hex, radix: 16) {
            result.append(byte)
          }
          index = content.index(nextIndex, offsetBy: 2)
        } else {
          index = content.index(after: index)
        }
      } else {
        if let byte = content[index].asciiValue {
          result.append(byte)
        }
        index = content.index(after: index)
      }
    }
    
    return result
  }
  
  private func validateJSON(_ data: Data) -> Bool {
    do {
      _ = try JSONDecoder().decode(JSONValue.self, from: data)
      return true
    } catch {
      return false
    }
  }
  
  private func validateXML(_ data: Data) -> Bool {
    do {
      _ = try XMLDocument(data: data)
      return true
    } catch {
      return false
    }
  }
  
  private func validateHTML(_ data: Data) -> Bool {
    // Basic HTML validation - just check if it can be parsed as XML
    // Real HTML validation would be more complex
    guard let content = String(data: data, encoding: .utf8) else {
      return false
    }
    
    // Very basic check for HTML-like structure
    return content.contains("<") && content.contains(">")
  }
}