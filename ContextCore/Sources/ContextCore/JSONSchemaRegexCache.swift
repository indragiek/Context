// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import RegexBuilder
import os

/// Thread-safe cache for compiled regular expressions
public actor JSONSchemaRegexCache {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "JSONSchemaRegexCache")
  private var cache: [String: Regex<AnyRegexOutput>] = [:]
  
  public static let shared = JSONSchemaRegexCache()
  
  /// Get or create a regex for the given pattern
  public func regex(for pattern: String) throws -> Regex<AnyRegexOutput> {
    // Try to get from cache first
    if let cached = cache[pattern] {
      return cached
    }
    
    // Check for dangerous patterns before compiling
    if isDangerousPattern(pattern) {
      logger.warning("Refusing to compile potentially dangerous regex pattern: \(pattern)")
      throw JSONSchemaValidationError.invalidSchema(reason: "Potentially dangerous regex pattern: \(pattern)")
    }
    
    // Not in cache, need to compile
    do {
      let regex = try Regex(pattern)
      
      // Store in cache
      cache[pattern] = regex
      
      logger.debug("Compiled and cached regex pattern: \(pattern)")
      return regex
    } catch {
      logger.error("Failed to compile regex pattern '\(pattern)': \(error)")
      throw JSONSchemaValidationError.invalidSchema(reason: "Invalid regex pattern: \(pattern)")
    }
  }
  
  /// Clear the cache
  public func clear() {
    cache.removeAll()
    logger.debug("Regex cache cleared")
  }
}

// MARK: - Common Format Regex Patterns

public struct JSONSchemaFormatRegexes {
  // Email validation (simplified but practical)
  nonisolated(unsafe) public static let email = #/^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/#
  
  // IPv4 address (no leading zeros except for single 0)
  nonisolated(unsafe) public static let ipv4 = #/^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$/#
  
  // IPv6 address (simplified)
  nonisolated(unsafe) public static let ipv6 = #/^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$/#
  
  // UUID
  nonisolated(unsafe) public static let uuid = #/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/#
  
  // Date format (YYYY-MM-DD)
  nonisolated(unsafe) public static let date = #/^\d{4}-\d{2}-\d{2}$/#
  
  // Time format (HH:MM:SS with optional fractional seconds and timezone)
  nonisolated(unsafe) public static let time = #/^([01]\d|2[0-3]):[0-5]\d:[0-5]\d(\.\d{1,9})?(Z|[+-]([01]\d|2[0-3]):[0-5]\d)?$/#
  
  // ISO 8601 Duration
  nonisolated(unsafe) public static let duration = #/^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/#
  
  // Hostname (RFC 1123) - simplified without lookbehind
  nonisolated(unsafe) public static let hostname = #/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/#
  
  // JSON Pointer (RFC 6901)
  nonisolated(unsafe) public static let jsonPointer = #/^(/(([^~/]|~0|~1)*))*$/#
  
  // Relative JSON Pointer
  nonisolated(unsafe) public static let relativeJsonPointer = #/^(0|[1-9][0-9]*)(#|(/(([^~/]|~0|~1)*))*)?$/#
  
  // URI Template (RFC 6570) - simplified
  nonisolated(unsafe) public static let uriTemplate = #/^[^{}]*(\{[^{}]+\}[^{}]*)*$/#
  
  // IRI - removed (proper validation is done in JSONSchemaFormatValidator)
}

// MARK: - String Extensions for Pattern Matching

extension String {
  /// Check if string matches a regex pattern (using cached regex)
  public func matchesPattern(_ pattern: String, timeout: TimeInterval = 2.0) async -> Bool {
    // Use the actor to check pattern matching
    return await JSONSchemaRegexCache.shared.matches(self, pattern: pattern, timeout: timeout)
  }
}

// Add extension to JSONSchemaRegexCache
extension JSONSchemaRegexCache {
  /// Check if a string matches a pattern with timeout protection
  public func matches(_ string: String, pattern: String, timeout: TimeInterval = 2.0) async -> Bool {
    // Implement timeout protection using Swift concurrency
    return await withTimeLimit(seconds: timeout, string: string, pattern: pattern) ?? false
  }
  
  /// Perform the actual regex matching
  private func performMatching(string: String, pattern: String) -> Bool {
    do {
      let regex = try regex(for: pattern)
      
      if pattern.hasPrefix("^") && pattern.hasSuffix("$") {
        return string.wholeMatch(of: regex) != nil
      } else if pattern.hasPrefix("^") {
        // Match from start
        if let match = string.firstMatch(of: regex) {
          return match.range.lowerBound == string.startIndex
        }
        return false
      } else if pattern.hasSuffix("$") {
        // Match to end
        if let match = string.firstMatch(of: regex) {
          return match.range.upperBound == string.endIndex
        }
        return false
      } else {
        // Match anywhere
        return string.contains(regex)
      }
    } catch {
      // If pattern compilation fails, consider it a non-match
      return false
    }
  }
  
  /// Execute regex matching with a time limit using Swift concurrency
  private func withTimeLimit(seconds: TimeInterval, string: String, pattern: String) async -> Bool? {
    return await withTaskGroup(of: Bool?.self) { group in
      // Add the main matching task
      group.addTask { [self] in
        return await self.performMatching(string: string, pattern: pattern)
      }
      
      // Add the timeout task
      group.addTask {
        try? await Task.sleep(for: .seconds(seconds))
        return nil
      }
      
      // Wait for the first task to complete
      for await result in group {
        if let value = result {
          group.cancelAll()
          return value
        } else {
          // This was the timeout task completing
          group.cancelAll()
          logger.warning("Regex matching timed out after \(seconds) seconds")
          return nil
        }
      }
      
      return nil
    }
  }
  
  /// Check for potentially dangerous regex patterns
  public func isDangerousPattern(_ pattern: String) -> Bool {
    // Check for common ReDoS patterns
    // Look for nested quantifiers: (x+)+, (x*)+, (x+)*, (x*)*, etc.
    if pattern.contains(")+") || pattern.contains(")*") || pattern.contains(")?") || pattern.contains("){"){ 
      // Check if this is actually a nested quantifier by looking for preceding quantifier
      var inGroup = false
      var hasQuantifierInGroup = false
      var escapeNext = false
      var i = pattern.startIndex
      
      while i < pattern.endIndex {
        let char = pattern[i]
        
        if escapeNext {
          escapeNext = false
          i = pattern.index(after: i)
          continue
        }
        
        if char == "\\" {
          escapeNext = true
          i = pattern.index(after: i)
          continue
        }
        
        if char == "(" {
          inGroup = true
          hasQuantifierInGroup = false
        } else if char == ")" {
          if hasQuantifierInGroup {
            // Check if there's a quantifier after this group
            let nextIndex = pattern.index(after: i)
            if nextIndex < pattern.endIndex {
              let nextChar = pattern[nextIndex]
              if nextChar == "+" || nextChar == "*" || nextChar == "?" || nextChar == "{" {
                logger.warning("Potentially dangerous nested quantifier pattern detected: \(pattern)")
                return true
              }
            }
          }
          inGroup = false
        } else if inGroup && (char == "+" || char == "*" || char == "?" || char == "{") {
          hasQuantifierInGroup = true
        }
        
        i = pattern.index(after: i)
      }
    }
    
    // Check for alternation with overlapping possibilities: (a|a*), (a|ab), etc.
    if pattern.contains("|") && pattern.contains("(") {
      // This is a complex pattern that could be dangerous
      let quantifierCount = pattern.filter { $0 == "+" || $0 == "*" || $0 == "?" }.count
      if quantifierCount > 2 {
        logger.warning("Complex alternation pattern with quantifiers detected: \(pattern)")
        return true
      }
    }
    
    // Check for patterns with character classes and nested quantifiers
    if pattern.contains("[") && pattern.contains("]") {
      // Look for patterns like ([a-z]+)+ or ([^x]*)*
      var i = pattern.startIndex
      var inCharClass = false
      var afterCharClass = false
      
      while i < pattern.endIndex {
        let char = pattern[i]
        
        if char == "[" {
          inCharClass = true
        } else if char == "]" {
          inCharClass = false
          afterCharClass = true
        } else if afterCharClass && !inCharClass {
          if char == "+" || char == "*" || char == "?" {
            // Found quantifier after character class, check if it's in a group with another quantifier
            let remaining = String(pattern[i...])
            if remaining.hasPrefix("+)+") || remaining.hasPrefix("+)*") || 
               remaining.hasPrefix("*)+") || remaining.hasPrefix("*)*") ||
               remaining.hasPrefix("?)+") || remaining.hasPrefix("?)*") {
              logger.warning("Nested character class quantifier detected: \(pattern)")
              return true
            }
          } else if char != ")" {
            afterCharClass = false
          }
        }
        
        i = pattern.index(after: i)
      }
    }
    
    // Check for excessive backtracking potential
    let quantifierCount = pattern.filter { $0 == "+" || $0 == "*" }.count
    let groupCount = pattern.filter { $0 == "(" }.count
    
    if quantifierCount > 3 && groupCount > 2 {
      logger.warning("Complex regex pattern with high backtracking potential: \(pattern)")
      return true
    }
    
    return false
  }
}