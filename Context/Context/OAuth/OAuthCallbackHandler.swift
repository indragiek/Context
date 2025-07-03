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
      // Validate parameter names and values
      guard let value = item.value, !value.isEmpty else { continue }

      switch item.name {
      case "code":
        // Basic validation of authorization code
        if value.count < 2048 {  // Reasonable limit for auth code
          code = value
        } else {
          logger.error("Authorization code exceeds maximum length")
        }
      case "state":
        // State should be base64url encoded
        state = value
      case "error":
        error = value
      case "error_description":
        errorDescription = value
      default:
        // Log unexpected parameters for security monitoring
        logger.warning("Unexpected parameter in OAuth callback: \(item.name)")
      }
    }

    // Must have either (code + state) or (error + state)
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
      logger.error("OAuth callback missing required parameters")
      return false
    }
  }
}
