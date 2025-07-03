// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// Represents user-provided configuration values for a DXT extension
public struct DXTUserConfigurationValues: Codable, Equatable, Sendable {
  /// Individual configuration value with metadata
  public struct ConfigValue: Codable, Equatable, Sendable {
    /// The actual value or keychain reference
    public enum Value: Codable, Equatable, Sendable {
      case string(String)
      case number(Double)
      case boolean(Bool)
      case stringArray([String])
      case keychainReference(UUID)
      
      private enum CodingKeys: String, CodingKey {
        case type
        case value
      }
      
      public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "string":
          let value = try container.decode(String.self, forKey: .value)
          self = .string(value)
        case "number":
          let value = try container.decode(Double.self, forKey: .value)
          self = .number(value)
        case "boolean":
          let value = try container.decode(Bool.self, forKey: .value)
          self = .boolean(value)
        case "stringArray":
          let value = try container.decode([String].self, forKey: .value)
          self = .stringArray(value)
        case "keychainReference":
          let value = try container.decode(UUID.self, forKey: .value)
          self = .keychainReference(value)
        default:
          throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown value type: \(type)")
        }
      }
      
      public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .string(let value):
          try container.encode("string", forKey: .type)
          try container.encode(value, forKey: .value)
        case .number(let value):
          try container.encode("number", forKey: .type)
          try container.encode(value, forKey: .value)
        case .boolean(let value):
          try container.encode("boolean", forKey: .type)
          try container.encode(value, forKey: .value)
        case .stringArray(let value):
          try container.encode("stringArray", forKey: .type)
          try container.encode(value, forKey: .value)
        case .keychainReference(let uuid):
          try container.encode("keychainReference", forKey: .type)
          try container.encode(uuid, forKey: .value)
        }
      }
    }
    
    /// The configuration value
    public var value: Value
    
    /// Whether this value contains sensitive data
    public var isSensitive: Bool
    
    /// The type of the configuration (string, number, boolean, directory, file)
    public var configType: String
    
    public init(value: Value, isSensitive: Bool, configType: String) {
      self.value = value
      self.isSensitive = isSensitive
      self.configType = configType
    }
  }
  
  /// Dictionary mapping configuration keys to their values
  public var values: [String: ConfigValue]
  
  public init(values: [String: ConfigValue] = [:]) {
    self.values = values
  }
  
  /// Returns a new instance with sensitive values replaced by keychain references
  /// - Parameter transform: A function that stores the sensitive value as JSON and returns a keychain reference UUID
  /// - Returns: A new instance with sensitive values replaced
  public func replacingSensitiveValues(using transform: (String, String) async throws -> UUID) async throws -> DXTUserConfigurationValues {
    var newValues: [String: ConfigValue] = [:]
    
    for (key, configValue) in values {
      if configValue.isSensitive {
        // Always store as JSON in keychain for consistency
        let jsonData: Data
        switch configValue.value {
        case .string(let value):
          jsonData = try JSONEncoder().encode(value)
        case .number(let value):
          jsonData = try JSONEncoder().encode(value)
        case .boolean(let value):
          jsonData = try JSONEncoder().encode(value)
        case .stringArray(let value):
          jsonData = try JSONEncoder().encode(value)
        case .keychainReference:
          // Already a reference, keep as is
          newValues[key] = configValue
          continue
        }
        
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
          // If encoding fails, keep original value
          newValues[key] = configValue
          continue
        }
        
        let uuid = try await transform(key, jsonString)
        newValues[key] = ConfigValue(
          value: .keychainReference(uuid),
          isSensitive: true,
          configType: configValue.configType
        )
      } else {
        newValues[key] = configValue
      }
    }
    
    return DXTUserConfigurationValues(values: newValues)
  }
  
  /// Returns a new instance with keychain references replaced by actual values
  /// - Parameters:
  ///   - manifest: The DXT manifest containing user config definitions
  ///   - transform: A function that retrieves the JSON value for a keychain reference UUID
  /// - Returns: A new instance with actual values restored
  public func resolvingKeychainReferences(manifest: DXTManifest? = nil, using transform: (UUID) async throws -> String?) async throws -> DXTUserConfigurationValues {
    var newValues: [String: ConfigValue] = [:]
    var missingKeys: [String] = []
    
    for (key, configValue) in values {
      if case .keychainReference(let uuid) = configValue.value {
        if let jsonString = try await transform(uuid),
           let jsonData = jsonString.data(using: .utf8) {
          // Decode based on the config type
          do {
            let decodedValue: ConfigValue.Value
            switch configValue.configType {
            case "string":
              let string = try JSONDecoder().decode(String.self, from: jsonData)
              decodedValue = .string(string)
            case "directory", "file":
              // Check if this config item supports multiple values
              if let manifestItem = manifest?.userConfig?[key],
                 manifestItem.multiple == true {
                // Decode as array
                let array = try JSONDecoder().decode([String].self, from: jsonData)
                decodedValue = .stringArray(array)
              } else {
                // Decode as single string
                let string = try JSONDecoder().decode(String.self, from: jsonData)
                decodedValue = .string(string)
              }
            case "number":
              let number = try JSONDecoder().decode(Double.self, from: jsonData)
              decodedValue = .number(number)
            case "boolean":
              let boolean = try JSONDecoder().decode(Bool.self, from: jsonData)
              decodedValue = .boolean(boolean)
            default:
              // Unknown type, try string as fallback
              let string = try JSONDecoder().decode(String.self, from: jsonData)
              decodedValue = .string(string)
            }
            
            newValues[key] = ConfigValue(
              value: decodedValue,
              isSensitive: false,  // After resolving from keychain, no longer sensitive
              configType: configValue.configType
            )
          } catch {
            // Failed to decode - track as missing
            missingKeys.append(key)
          }
        } else {
          // Value missing from keychain - track it
          missingKeys.append(key)
        }
      } else {
        newValues[key] = configValue
      }
    }
    
    // Return instance without missing keys
    return DXTUserConfigurationValues(values: newValues)
  }
  
  /// Checks if all sensitive values are keychain references (not actual values)
  public var containsSensitiveValues: Bool {
    for (_, configValue) in values {
      if configValue.isSensitive {
        if case .keychainReference = configValue.value {
          // This is OK - sensitive value is stored as reference
          continue
        } else {
          // Sensitive value is stored directly - this is not allowed
          return true
        }
      }
    }
    return false
  }
  
  /// Returns the missing required keys based on the manifest
  public func missingRequiredKeys(from manifest: DXTManifest) -> [String] {
    guard let userConfig = manifest.userConfig else { return [] }
    
    var missing: [String] = []
    for (key, configItem) in userConfig {
      if configItem.required == true && values[key] == nil {
        missing.append(key)
      }
    }
    return missing
  }
  
  /// Validates that number values are within their specified ranges
  /// Returns an array of validation errors (empty if all valid)
  public func validateNumberRanges(from manifest: DXTManifest) -> [String] {
    guard let userConfig = manifest.userConfig else { return [] }
    
    var errors: [String] = []
    for (key, configValue) in values {
      guard let configItem = userConfig[key] else { continue }
      
      // Only validate number types
      guard configItem.type == "number" else { continue }
      
      // Extract the number value
      let numberValue: Double?
      switch configValue.value {
      case .number(let value):
        numberValue = value
      case .string(let value):
        // Try to parse string as number for flexibility
        numberValue = Double(value)
      default:
        numberValue = nil
      }
      
      guard let value = numberValue else {
        errors.append("\(key): Value must be a number")
        continue
      }
      
      // Check minimum constraint
      if let min = configItem.min, value < min {
        errors.append("\(key): Value \(value) is below minimum \(min)")
      }
      
      // Check maximum constraint
      if let max = configItem.max, value > max {
        errors.append("\(key): Value \(value) is above maximum \(max)")
      }
    }
    
    return errors
  }
  
  /// Validates file and directory paths
  /// Returns an array of validation errors (empty if all valid)
  public func validatePaths(from manifest: DXTManifest) -> [String] {
    guard let userConfig = manifest.userConfig else { return [] }
    let fileManager = FileManager.default
    
    var errors: [String] = []
    for (key, configValue) in values {
      guard let configItem = userConfig[key] else { continue }
      
      // Only validate file and directory types
      guard configItem.type == "file" || configItem.type == "directory" else { continue }
      
      let paths: [String]
      switch configValue.value {
      case .string(let path):
        paths = [path]
      case .stringArray(let pathArray):
        paths = pathArray
      default:
        continue
      }
      
      for path in paths {
        // Skip empty paths
        guard !path.isEmpty else { continue }
        
        // Expand tilde and environment variables
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        // Check if path exists
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory)
        
        if configItem.required == true && !exists {
          errors.append("\(key): Path does not exist: \(path)")
        } else if exists {
          // If it exists, verify it's the correct type
          if configItem.type == "directory" && !isDirectory.boolValue {
            errors.append("\(key): Path is not a directory: \(path)")
          } else if configItem.type == "file" && isDirectory.boolValue {
            errors.append("\(key): Path is not a file: \(path)")
          }
        }
      }
    }
    
    return errors
  }
}

// Extend DXTUserConfigurationValues to conform to JSONRepresentable
extension DXTUserConfigurationValues: JSONRepresentable {
  public var jsonValue: JSONValue {
    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(self)
      let jsonValueDecoded = try JSONValue(decoding: data)
      return jsonValueDecoded
    } catch {
      // If encoding fails, return null
      return .null
    }
  }
}