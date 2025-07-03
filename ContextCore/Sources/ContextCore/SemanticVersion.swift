// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// A semantic version according to the Semantic Versioning 2.0.0 specification.
/// See: https://semver.org/
public struct SemanticVersion {
  /// The major version number
  public let major: Int
  /// The minor version number
  public let minor: Int
  /// The patch version number
  public let patch: Int
  /// The pre-release version identifiers
  public let prerelease: [String]
  /// The build metadata identifiers
  public let buildMetadata: [String]
  
  /// Initialize a semantic version with components
  public init(major: Int, minor: Int = 0, patch: Int = 0, prerelease: [String] = [], buildMetadata: [String] = []) {
    precondition(major >= 0, "Major version must be non-negative")
    precondition(minor >= 0, "Minor version must be non-negative")
    precondition(patch >= 0, "Patch version must be non-negative")
    
    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
    self.buildMetadata = buildMetadata
  }
  
  /// Parse a semantic version from a string
  public init?(string: String) {
    // Check for empty string
    guard !string.isEmpty else { return nil }
    
    // Split off build metadata first (everything after +)
    let parts = string.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    let versionAndPrerelease = parts[0]
    
    // Check for empty build metadata
    if parts.count > 1 && parts[1].isEmpty {
      return nil
    }
    
    let buildMeta = parts.count > 1 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
    
    // Split version and pre-release (everything after -)
    let versionParts = versionAndPrerelease.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    let versionCore = versionParts[0]
    
    // Check for empty pre-release
    if versionParts.count > 1 && versionParts[1].isEmpty {
      return nil
    }
    
    let prereleasePart = versionParts.count > 1 ? versionParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
    
    // Parse core version numbers
    let numberStrings = versionCore.split(separator: ".")
    guard numberStrings.count >= 1 && numberStrings.count <= 3 else { return nil }
    
    var numbers: [Int] = []
    for numStr in numberStrings {
      // Check if it's a valid number
      guard let num = Int(numStr) else { return nil }
      
      // Verify no leading zeros
      if numStr.count > 1 && numStr.hasPrefix("0") {
        return nil // Leading zeros not allowed
      }
      
      numbers.append(num)
    }
    
    let major = numbers[0]
    let minor = numbers.count > 1 ? numbers[1] : 0
    let patch = numbers.count > 2 ? numbers[2] : 0
    
    // Validate pre-release identifiers
    for identifier in prereleasePart {
      if identifier.isEmpty { return nil }
      // Check if it's a numeric identifier
      if let num = Int(identifier) {
        // Numeric identifiers must not have leading zeros
        if identifier.count > 1 && identifier.hasPrefix("0") && num != 0 {
          return nil
        }
      }
      // Check for valid characters (alphanumerics and hyphens)
      let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
      if identifier.unicodeScalars.contains(where: { !validChars.contains($0) }) {
        return nil
      }
    }
    
    // Validate build metadata identifiers
    for identifier in buildMeta {
      if identifier.isEmpty { return nil }
      // Check for valid characters (alphanumerics and hyphens)
      let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
      if identifier.unicodeScalars.contains(where: { !validChars.contains($0) }) {
        return nil
      }
    }
    
    self.init(major: major, minor: minor, patch: patch, prerelease: prereleasePart, buildMetadata: buildMeta)
  }
  
  /// String representation of the version
  public var versionString: String {
    var result = "\(major).\(minor).\(patch)"
    if !prerelease.isEmpty {
      result += "-" + prerelease.joined(separator: ".")
    }
    if !buildMetadata.isEmpty {
      result += "+" + buildMetadata.joined(separator: ".")
    }
    return result
  }
}

// MARK: - Equatable

extension SemanticVersion: Equatable {
  public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    // Build metadata MUST be ignored when determining version equality
    return lhs.major == rhs.major &&
           lhs.minor == rhs.minor &&
           lhs.patch == rhs.patch &&
           lhs.prerelease == rhs.prerelease
  }
}

// MARK: - Comparable

extension SemanticVersion: Comparable {
  public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    // Compare major version
    if lhs.major != rhs.major {
      return lhs.major < rhs.major
    }
    
    // Compare minor version
    if lhs.minor != rhs.minor {
      return lhs.minor < rhs.minor
    }
    
    // Compare patch version
    if lhs.patch != rhs.patch {
      return lhs.patch < rhs.patch
    }
    
    // When major, minor, and patch are equal, a pre-release version has lower precedence than a normal version
    if lhs.prerelease.isEmpty && !rhs.prerelease.isEmpty {
      return false // lhs is normal version, rhs is pre-release
    }
    if !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty {
      return true // lhs is pre-release, rhs is normal version
    }
    
    // Compare pre-release versions
    if !lhs.prerelease.isEmpty && !rhs.prerelease.isEmpty {
      return comparePrerelease(lhs.prerelease, rhs.prerelease)
    }
    
    // Build metadata MUST be ignored when determining version precedence
    return false // versions are equal
  }
  
  private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Bool {
    // Compare each identifier from left to right
    let minCount = min(lhs.count, rhs.count)
    
    for i in 0..<minCount {
      let lhsIdentifier = lhs[i]
      let rhsIdentifier = rhs[i]
      
      // Check if both are numeric
      if let lhsNum = Int(lhsIdentifier), let rhsNum = Int(rhsIdentifier) {
        if lhsNum != rhsNum {
          return lhsNum < rhsNum
        }
      } else if Int(lhsIdentifier) != nil {
        // lhs is numeric, rhs is not - numeric identifiers always have lower precedence
        return true
      } else if Int(rhsIdentifier) != nil {
        // rhs is numeric, lhs is not
        return false
      } else {
        // Both are non-numeric, compare lexically
        if lhsIdentifier != rhsIdentifier {
          return lhsIdentifier < rhsIdentifier
        }
      }
    }
    
    // A larger set of pre-release fields has a higher precedence than a smaller set
    return lhs.count < rhs.count
  }
}

// MARK: - Version Requirement Checking

public extension SemanticVersion {
  /// Check if this version satisfies a requirement string
  /// Supports operators: >=, >, <=, <, ==, ~> (pessimistic operator)
  /// Can handle multiple requirements separated by spaces (AND) or || (OR)
  func satisfies(_ requirement: String) -> Bool {
    // Handle OR conditions first
    if requirement.contains("||") {
      let orParts = requirement.split(separator: "||").map { $0.trimmingCharacters(in: .whitespaces) }
      return orParts.contains { satisfiesSingleRequirement($0) }
    }
    
    // For single requirements or operators with spaces (like "~> 1.2.3"), treat as single requirement
    let trimmed = requirement.trimmingCharacters(in: .whitespaces)
    
    // Split on spaces to check for multiple requirements
    let parts = trimmed.split(separator: " ").map(String.init)
    
    // If only one part, it's definitely a single requirement
    if parts.count == 1 {
      return satisfiesSingleRequirement(parts[0])
    }
    
    // Check if this is a single operator with spaces (like "~> 1.2.3")
    // This happens when we have exactly 2 parts and the first is just an operator
    let operators = [">=", ">", "<=", "<", "==", "~>"]
    if parts.count == 2 && operators.contains(parts[0]) {
      // It's a single requirement with space between operator and version
      return satisfiesSingleRequirement(trimmed)
    }
    
    // Check if any parts start with an operator (indicating multiple requirements)
    let hasMultipleRequirements = parts.count > 1 && parts.contains { part in
      operators.contains(where: { part.hasPrefix($0) })
    }
    
    if hasMultipleRequirements {
      // Parse as multiple requirements
      // Need to combine operator with version that follows
      var requirements: [String] = []
      var i = 0
      while i < parts.count {
        let part = parts[i]
        if operators.contains(where: { part.hasPrefix($0) }) {
          // This part has an operator
          // Find which operator it is
          let matchedOp = operators.first { part.hasPrefix($0) }!
          if part.count > matchedOp.count {
            // Operator and version are together (e.g., ">=1.0.0" or "<4")
            requirements.append(part)
          } else if i + 1 < parts.count {
            // Operator and version are separate (e.g., ">=" "1.0.0")
            requirements.append(part + parts[i + 1])
            i += 1
          } else {
            // Operator without version
            requirements.append(part)
          }
        } else {
          // No operator, treat as exact version match
          requirements.append(part)
        }
        i += 1
      }
      return requirements.allSatisfy { satisfiesSingleRequirement($0) }
    } else {
      // Treat the whole thing as a single requirement
      return satisfiesSingleRequirement(trimmed)
    }
  }
  
  private func satisfiesSingleRequirement(_ requirement: String) -> Bool {
    let trimmed = requirement.trimmingCharacters(in: .whitespaces)
    
    // Handle pessimistic operator ~>
    if trimmed.hasPrefix("~>") {
      let versionStr = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      guard let requiredVersion = SemanticVersion(string: versionStr) else { return false }
      
      // Count the components in the original version string to determine behavior
      let componentCount = versionStr.split(separator: ".").count
      
      if componentCount >= 3 {
        // ~> 1.2.3 means >= 1.2.3 and < 1.3.0 (can increment patch version)
        let nextMinor = SemanticVersion(major: requiredVersion.major, minor: requiredVersion.minor + 1, patch: 0)
        return self >= requiredVersion && self < nextMinor
      } else if componentCount == 2 {
        // ~> 1.2 means >= 1.2.0 and < 2.0.0 (can increment minor and patch version)
        let nextMajor = SemanticVersion(major: requiredVersion.major + 1, minor: 0, patch: 0)
        return self >= requiredVersion && self < nextMajor
      } else if componentCount == 1 {
        // ~> 1 means >= 1.0.0 (no upper bound in this implementation)
        return self >= requiredVersion
      }
      
      return false
    }
    
    // Handle other operators
    if trimmed.hasPrefix(">=") {
      let versionStr = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      guard let requiredVersion = SemanticVersion(string: versionStr) else { return false }
      return self >= requiredVersion
    } else if trimmed.hasPrefix(">") {
      let versionStr = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
      guard let requiredVersion = SemanticVersion(string: versionStr) else { return false }
      return self > requiredVersion
    } else if trimmed.hasPrefix("<=") {
      let versionStr = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      guard let requiredVersion = SemanticVersion(string: versionStr) else { return false }
      return self <= requiredVersion
    } else if trimmed.hasPrefix("<") {
      let versionStr = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
      guard let requiredVersion = SemanticVersion(string: versionStr) else { return false }
      return self < requiredVersion
    } else if trimmed.hasPrefix("==") {
      let versionStr = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      guard let requiredVersion = SemanticVersion(string: versionStr) else { return false }
      return self == requiredVersion
    } else {
      // No operator, assume exact match
      guard let requiredVersion = SemanticVersion(string: trimmed) else { return false }
      return self == requiredVersion
    }
  }
}

// MARK: - CustomStringConvertible

extension SemanticVersion: CustomStringConvertible {
  public var description: String {
    return versionString
  }
}
