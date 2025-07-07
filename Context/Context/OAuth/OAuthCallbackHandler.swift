// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import SwiftUI
import os

/// Handles OAuth callback URLs for the app.contextmcp:// URL scheme.
@MainActor
@Observable
final class OAuthCallbackHandler {
  static let shared = OAuthCallbackHandler()

  /// Property that emits OAuth callbacks
  var pendingCallback: OAuthCallback?

  struct OAuthCallback: Equatable {
    let code: String
    let state: String
    let error: String?
    let errorDescription: String?
  }

  private let logger = Logger(subsystem: "com.indragie.Context", category: "OAuthCallbackHandler")

  private init() {}

  /// Handles an OAuth callback URL.
  ///
  /// Expected format: app.contextmcp://oauth/callback?code=XXX&state=YYY
  /// or error format: app.contextmcp://oauth/callback?error=XXX&error_description=YYY&state=ZZZ
  func handleURL(_ url: URL) -> Bool {
    // Strict validation of callback URL structure
    guard url.scheme == OAuthConstants.urlScheme,
      url.host == OAuthConstants.callbackHost,
      url.path == OAuthConstants.callbackPath
    else {
      logger.warning("Received URL with incorrect structure: \(url, privacy: .private)")
      return false
    }

    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      logger.error("Failed to parse callback URL components")
      return false
    }

    let queryItems = components.queryItems ?? []
    var code: String?
    var state: String?
    var error: String?
    var errorDescription: String?

    // Parse query parameters
    for item in queryItems {
      guard let value = item.value, !value.isEmpty else {
        logger.warning("OAuth callback parameter '\(item.name)' has empty or missing value")
        continue
      }

      switch item.name {
      case "code":
        // Authorization code validation per RFC 6749
        if isValidAuthorizationCode(value) {
          code = value
        } else {
          logger.error("Invalid authorization code format")
          pendingCallback = OAuthCallback(
            code: "",
            state: state ?? "",
            error: "invalid_request",
            errorDescription: "Authorization code contains invalid characters"
          )
          return true
        }
      case "state":
        // State parameter validation per RFC 6749
        if isValidStateParameter(value) {
          state = value
        } else {
          logger.error("Invalid state parameter format")
          pendingCallback = OAuthCallback(
            code: "",
            state: "",
            error: "invalid_request", 
            errorDescription: "State parameter contains invalid characters"
          )
          return true
        }
      case "error":
        // Error code validation per RFC 6749
        if isValidErrorCode(value) {
          error = value
        } else {
          logger.warning("Non-standard OAuth error code: \(value)")
          error = value  // Accept but log warning
        }
      case "error_description":
        errorDescription = value
      default:
        // Log unexpected parameters for security monitoring
        logger.warning("Unexpected parameter in OAuth callback: \(item.name)")
      }
    }

    // Validate callback completion
    if let code = code, let state = state {
      pendingCallback = OAuthCallback(
        code: code,
        state: state,
        error: nil,
        errorDescription: nil
      )
      logger.info("Successfully parsed OAuth callback with authorization code")
      return true
    } else if let error = error, let state = state {
      pendingCallback = OAuthCallback(
        code: "",
        state: state,
        error: error,
        errorDescription: errorDescription
      )
      logger.info("Parsed OAuth callback with error: \(error)")
      return true
    } else {
      // Provide specific error information
      let missingParams = [
        code == nil ? "code" : nil,
        state == nil ? "state" : nil,
        error == nil && code == nil ? "error" : nil
      ].compactMap { $0 }
      
      let errorMsg = "OAuth callback missing required parameters: \(missingParams.joined(separator: ", "))"
      logger.error("\(errorMsg, privacy: .public)")
      
      pendingCallback = OAuthCallback(
        code: "",
        state: state ?? "",
        error: "invalid_request",
        errorDescription: errorMsg
      )
      return true
    }
  }
  
  // MARK: - Parameter Validation
  
  /// Validates authorization code format per RFC 6749
  private func isValidAuthorizationCode(_ code: String) -> Bool {
    // RFC 6749: authorization codes are typically URL-safe strings
    // Allow alphanumeric, hyphens, periods, underscores, tildes, and URL-encoded chars
    let allowedCharacters = CharacterSet.alphanumerics
      .union(CharacterSet(charactersIn: "-._~%"))
    return code.rangeOfCharacter(from: allowedCharacters.inverted) == nil
  }
  
  /// Validates state parameter format per RFC 6749
  private func isValidStateParameter(_ state: String) -> Bool {
    // RFC 6749: state should be an unguessable random string
    // Allow alphanumeric, hyphens, periods, underscores, tildes, and URL-encoded chars
    let allowedCharacters = CharacterSet.alphanumerics
      .union(CharacterSet(charactersIn: "-._~%+/="))
    return state.rangeOfCharacter(from: allowedCharacters.inverted) == nil
  }
  
  /// Validates error code against RFC 6749 standard error codes
  private func isValidErrorCode(_ error: String) -> Bool {
    let standardErrorCodes = [
      "invalid_request",
      "unauthorized_client", 
      "access_denied",
      "unsupported_response_type",
      "invalid_scope",
      "server_error",
      "temporarily_unavailable"
    ]
    return standardErrorCodes.contains(error)
  }
}
