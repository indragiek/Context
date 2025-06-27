// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation
import Security
import os

/// Manages secure storage of OAuth tokens in the macOS Keychain.
actor KeychainManager {
  private let serviceName: String
  private let logger: Logger

  /// Maximum allowed token data size (1MB)
  private let maxTokenDataSize = 1_048_576

  /// Errors thrown by KeychainManager.
  enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case unexpectedData
    case unhandledError(status: OSStatus)
    case tokenDataTooLarge
    case tokenExpired
    case invalidTokenData

    var errorDescription: String? {
      switch self {
      case .itemNotFound:
        return "Token not found in keychain"
      case .unexpectedData:
        return "Unexpected data format in keychain"
      case .unhandledError(let status):
        if let errorMessage = SecCopyErrorMessageString(status, nil) as String? {
          return "Keychain error: \(errorMessage)"
        }
        return "Unknown keychain error (status: \(status))"
      case .tokenDataTooLarge:
        return "Token data exceeds maximum allowed size"
      case .tokenExpired:
        return "Token has expired"
      case .invalidTokenData:
        return "Token data is invalid or corrupted"
      }
    }
  }

  init(
    serviceName: String = "com.indragie.Context.OAuth",
    logger: Logger = Logger(subsystem: "com.indragie.Context", category: "KeychainManager")
  ) {
    self.serviceName = serviceName
    self.logger = logger
  }

  /// Validates token data before storage
  private func validateToken(_ token: OAuthToken) throws {
    if let expiresAt = token.expiresAt, expiresAt < Date() {
      throw KeychainError.tokenExpired
    }

    guard !token.accessToken.isEmpty else {
      throw KeychainError.invalidTokenData
    }

    guard !token.tokenType.isEmpty else {
      throw KeychainError.invalidTokenData
    }
  }

  /// Stores an OAuth token in the keychain for a specific server.
  ///
  /// - Parameters:
  ///   - token: The OAuth token to store.
  ///   - serverID: The unique identifier of the server.
  ///   - clientID: The OAuth client ID used to obtain this token.
  func storeToken(for serverID: UUID, token: OAuthToken, clientID: String) async throws {
    try validateToken(token)

    let account = serverID.uuidString

    let storedToken = StoredOAuthToken(token: token, clientID: clientID)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let tokenData = try encoder.encode(storedToken)

    guard tokenData.count <= maxTokenDataSize else {
      logger.error("Token data too large for server \(serverID): \(tokenData.count) bytes")
      throw KeychainError.tokenDataTooLarge
    }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
      kSecValueData as String: tokenData,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrSynchronizable as String: false,
      kSecAttrLabel as String: "OAuth Token",
      kSecAttrDescription as String: "Secure OAuth token storage",
      kSecAttrCreationDate as String: Date() as NSDate,
      kSecAttrModificationDate as String: Date() as NSDate,
    ]

    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
    ]

    _ = SecItemDelete(deleteQuery as CFDictionary)

    let status = SecItemAdd(query as CFDictionary, nil)

    if status != errSecSuccess {
      logger.error("Failed to store token in keychain for server \(serverID): \(status)")
      throw KeychainError.unhandledError(status: status)
    }

    logger.info("Successfully stored token in keychain for server \(serverID)")
  }

  /// Retrieves stored OAuth token data from the keychain for a specific server.
  ///
  /// - Parameter serverID: The unique identifier of the server.
  /// - Returns: The stored OAuth token data if found and valid, nil otherwise.
  func retrieveStoredToken(for serverID: UUID) async throws -> StoredOAuthToken? {
    let account = serverID.uuidString

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
        logger.error("Unexpected keychain data format for server \(serverID)")
        throw KeychainError.unexpectedData
      }

      guard data.count <= maxTokenDataSize else {
        logger.error("Retrieved token data exceeds maximum size for server \(serverID)")
        throw KeychainError.unexpectedData
      }

      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      do {
        // Try to decode as StoredOAuthToken first (new format)
        if let storedToken = try? decoder.decode(StoredOAuthToken.self, from: data) {
          if let expiresAt = storedToken.token.expiresAt, expiresAt < Date() {
            logger.warning("Retrieved expired token for server \(serverID)")
            try? await deleteToken(for: serverID)
            throw KeychainError.tokenExpired
          }

          logger.info(
            "Successfully retrieved valid token with client ID from keychain for server \(serverID)"
          )
          return storedToken
        }

        // Fallback to legacy format (just OAuthToken)
        let token = try decoder.decode(OAuthToken.self, from: data)

        if let expiresAt = token.expiresAt, expiresAt < Date() {
          logger.warning("Retrieved expired token for server \(serverID)")
          try? await deleteToken(for: serverID)
          throw KeychainError.tokenExpired
        }

        logger.info(
          "Successfully retrieved legacy token from keychain for server \(serverID), using default client ID"
        )
        // Return with default client ID for legacy tokens
        return StoredOAuthToken(token: token, clientID: "com.indragie.Context")
      } catch let decodingError as DecodingError {
        logger.error(
          "Failed to decode token from keychain for server \(serverID): \(decodingError)")
        throw KeychainError.unexpectedData
      } catch {
        throw error
      }

    case errSecItemNotFound:
      logger.debug("No token found in keychain for server \(serverID)")
      return nil

    case errSecAuthFailed:
      logger.error("Authentication failed when accessing keychain for server \(serverID)")
      throw KeychainError.unhandledError(status: status)

    default:
      logger.error("Failed to retrieve token from keychain for server \(serverID): \(status)")
      throw KeychainError.unhandledError(status: status)
    }
  }

  /// Retrieves just the OAuth token from the keychain for a specific server (backward compatibility).
  ///
  /// - Parameter serverID: The unique identifier of the server.
  /// - Returns: The OAuth token if found and valid, nil otherwise.
  func retrieveToken(for serverID: UUID) async throws -> OAuthToken? {
    guard let storedToken = try await retrieveStoredToken(for: serverID) else {
      return nil
    }
    return storedToken.token
  }

  /// Deletes an OAuth token from the keychain for a specific server.
  ///
  /// - Parameter serverID: The unique identifier of the server.
  func deleteToken(for serverID: UUID) async throws {
    let account = serverID.uuidString

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
    ]

    let status = SecItemDelete(query as CFDictionary)

    switch status {
    case errSecSuccess:
      logger.info("Successfully deleted token from keychain for server \(serverID)")

    case errSecItemNotFound:
      logger.debug("Token already absent from keychain for server \(serverID)")

    case errSecAuthFailed:
      logger.error("Authentication failed when deleting token for server \(serverID)")
      throw KeychainError.unhandledError(status: status)

    default:
      logger.error("Failed to delete token from keychain for server \(serverID): \(status)")
      throw KeychainError.unhandledError(status: status)
    }
  }

  /// Deletes all OAuth tokens from the keychain.
  func deleteAllTokens() async throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
    ]

    let status = SecItemDelete(query as CFDictionary)

    switch status {
    case errSecSuccess:
      logger.info("Successfully deleted all tokens from keychain")

    case errSecItemNotFound:
      logger.debug("No tokens found to delete from keychain")

    case errSecAuthFailed:
      logger.error("Authentication failed when deleting all tokens")
      throw KeychainError.unhandledError(status: status)

    default:
      logger.error("Failed to delete all tokens from keychain: \(status)")
      throw KeychainError.unhandledError(status: status)
    }
  }

  /// Checks if a token exists for a specific server without retrieving it.
  ///
  /// - Parameter serverID: The unique identifier of the server.
  /// - Returns: True if a token exists, false otherwise.
  func hasToken(for serverID: UUID) async -> Bool {
    let account = serverID.uuidString

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
