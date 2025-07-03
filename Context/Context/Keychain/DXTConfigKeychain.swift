// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Security
import os

/// Manages secure storage of sensitive DXT user configuration values in the macOS Keychain.
actor DXTConfigKeychain {
  private let serviceName: String
  private let logger: Logger
  
  /// Maximum allowed value data size (1MB)
  private let maxValueDataSize = 1_048_576
  
  /// Errors thrown by DXTConfigKeychain.
  enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case unexpectedData
    case unhandledError(status: OSStatus)
    case valueDataTooLarge
    case invalidValueData
    
    var errorDescription: String? {
      switch self {
      case .itemNotFound:
        return "Configuration value not found in keychain"
      case .unexpectedData:
        return "Unexpected data format in keychain"
      case .unhandledError(let status):
        if let errorMessage = SecCopyErrorMessageString(status, nil) as String? {
          return "Keychain error: \(errorMessage)"
        }
        return "Unknown keychain error (status: \(status))"
      case .valueDataTooLarge:
        return "Configuration value data exceeds maximum allowed size"
      case .invalidValueData:
        return "Configuration value data is invalid or corrupted"
      }
    }
  }
  
  init(
    serviceName: String = "com.indragie.Context.DXTConfig",
    logger: Logger = Logger(subsystem: "com.indragie.Context", category: "DXTConfigKeychain")
  ) {
    self.serviceName = serviceName
    self.logger = logger
  }
  
  /// Stores a sensitive configuration value in the keychain.
  ///
  /// - Parameters:
  ///   - value: The JSON-encoded value to store.
  ///   - identifier: The unique identifier (UUID) for this value.
  func storeValue(_ value: String, for identifier: UUID) async throws {
    guard !value.isEmpty else {
      throw KeychainError.invalidValueData
    }
    
    guard let valueData = value.data(using: .utf8) else {
      throw KeychainError.invalidValueData
    }
    
    guard valueData.count <= maxValueDataSize else {
      logger.error("Value data too large for identifier \(identifier): \(valueData.count) bytes")
      throw KeychainError.valueDataTooLarge
    }
    
    let account = identifier.uuidString
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
      kSecValueData as String: valueData,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrSynchronizable as String: false,
      kSecAttrLabel as String: "DXT Configuration Value",
      kSecAttrDescription as String: "Secure DXT user configuration value storage",
      kSecAttrCreationDate as String: Date() as NSDate,
      kSecAttrModificationDate as String: Date() as NSDate,
    ]
    
    // Delete any existing item first
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
    ]
    
    _ = SecItemDelete(deleteQuery as CFDictionary)
    
    let status = SecItemAdd(query as CFDictionary, nil)
    
    if status != errSecSuccess {
      logger.error("Failed to store value in keychain for identifier \(identifier): \(status)")
      throw KeychainError.unhandledError(status: status)
    }
    
    logger.info("Successfully stored value in keychain for identifier \(identifier)")
  }
  
  /// Retrieves a sensitive configuration value from the keychain.
  ///
  /// - Parameter identifier: The unique identifier (UUID) for this value.
  /// - Returns: The JSON-encoded value if found, nil otherwise.
  func retrieveValue(for identifier: UUID) async throws -> String? {
    let account = identifier.uuidString
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    
    switch status {
    case errSecSuccess:
      guard let result = item as? [String: Any],
            let data = result[kSecValueData as String] as? Data
      else {
        logger.error("Unexpected keychain data format for identifier \(identifier)")
        throw KeychainError.unexpectedData
      }
      
      guard data.count <= maxValueDataSize else {
        logger.error("Retrieved value data exceeds maximum size for identifier \(identifier)")
        throw KeychainError.unexpectedData
      }
      
      guard let value = String(data: data, encoding: .utf8) else {
        logger.error("Failed to decode value data as UTF-8 for identifier \(identifier)")
        throw KeychainError.unexpectedData
      }
      
      logger.info("Successfully retrieved value from keychain for identifier \(identifier)")
      return value
      
    case errSecItemNotFound:
      logger.debug("No value found in keychain for identifier \(identifier)")
      return nil
      
    case errSecAuthFailed:
      logger.error("Authentication failed when accessing keychain for identifier \(identifier)")
      throw KeychainError.unhandledError(status: status)
      
    default:
      logger.error("Failed to retrieve value from keychain for identifier \(identifier): \(status)")
      throw KeychainError.unhandledError(status: status)
    }
  }
  
  /// Deletes a sensitive configuration value from the keychain.
  ///
  /// - Parameter identifier: The unique identifier (UUID) for this value.
  func deleteValue(for identifier: UUID) async throws {
    let account = identifier.uuidString
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    
    switch status {
    case errSecSuccess:
      logger.info("Successfully deleted value from keychain for identifier \(identifier)")
      
    case errSecItemNotFound:
      logger.debug("Value already absent from keychain for identifier \(identifier)")
      
    case errSecAuthFailed:
      logger.error("Authentication failed when deleting value for identifier \(identifier)")
      throw KeychainError.unhandledError(status: status)
      
    default:
      logger.error("Failed to delete value from keychain for identifier \(identifier): \(status)")
      throw KeychainError.unhandledError(status: status)
    }
  }
  
  /// Deletes all DXT configuration values from the keychain.
  func deleteAllValues() async throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    
    switch status {
    case errSecSuccess:
      logger.info("Successfully deleted all DXT configuration values from keychain")
      
    case errSecItemNotFound:
      logger.debug("No DXT configuration values found to delete from keychain")
      
    case errSecAuthFailed:
      logger.error("Authentication failed when deleting all values")
      throw KeychainError.unhandledError(status: status)
      
    default:
      logger.error("Failed to delete all values from keychain: \(status)")
      throw KeychainError.unhandledError(status: status)
    }
  }
  
  /// Checks if a value exists for a specific identifier without retrieving it.
  ///
  /// - Parameter identifier: The unique identifier (UUID) for this value.
  /// - Returns: True if a value exists, false otherwise.
  func hasValue(for identifier: UUID) async -> Bool {
    let account = identifier.uuidString
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess
  }
}