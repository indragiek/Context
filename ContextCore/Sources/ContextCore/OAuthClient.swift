// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import CryptoKit
import Foundation
import os

/// OAuth 2.0 token response.
public struct OAuthToken: Codable, Sendable, Equatable {
  /// The access token issued by the authorization server.
  public let accessToken: String

  /// The type of token issued (typically "Bearer").
  public let tokenType: String

  /// The lifetime in seconds of the access token.
  public let expiresIn: Int?

  /// The refresh token, which can be used to obtain new access tokens.
  public let refreshToken: String?

  /// The scope of the access token.
  public let scope: String?

  /// Computed expiration date based on when the token was received.
  public let expiresAt: Date?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case tokenType = "token_type"
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
    case scope
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.accessToken = try container.decode(String.self, forKey: .accessToken)
    self.tokenType = try container.decode(String.self, forKey: .tokenType)
    self.expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
    self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
    self.scope = try container.decodeIfPresent(String.self, forKey: .scope)

    // Calculate expiration date
    if let expiresIn = expiresIn {
      self.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
    } else {
      self.expiresAt = nil
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(accessToken, forKey: .accessToken)
    try container.encode(tokenType, forKey: .tokenType)
    try container.encodeIfPresent(expiresIn, forKey: .expiresIn)
    try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
    try container.encodeIfPresent(scope, forKey: .scope)
  }

  /// Whether the token has expired.
  public var isExpired: Bool {
    guard let expiresAt = expiresAt else { return false }
    return Date() >= expiresAt
  }
}

/// OAuth 2.0 authorization server metadata as defined in RFC 8414.
public struct AuthorizationServerMetadata: Codable, Sendable, Equatable {
  /// The authorization server's issuer identifier.
  public let issuer: String

  /// URL of the authorization server's authorization endpoint.
  public let authorizationEndpoint: URL?

  /// URL of the authorization server's token endpoint.
  public let tokenEndpoint: URL?

  /// JSON array containing a list of the OAuth 2.0 response_type values supported.
  public let responseTypesSupported: [String]?

  /// JSON array containing a list of the OAuth 2.0 grant_type values supported.
  public let grantTypesSupported: [String]?

  /// JSON array containing a list of PKCE code challenge methods supported.
  public let codeChallengeMethodsSupported: [String]?

  /// URL of the authorization server's dynamic client registration endpoint.
  public let registrationEndpoint: URL?

  enum CodingKeys: String, CodingKey {
    case issuer
    case authorizationEndpoint = "authorization_endpoint"
    case tokenEndpoint = "token_endpoint"
    case responseTypesSupported = "response_types_supported"
    case grantTypesSupported = "grant_types_supported"
    case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    case registrationEndpoint = "registration_endpoint"
  }
}

/// OAuth 2.0 protected resource metadata as defined in RFC 9728.
public struct ProtectedResourceMetadata: Codable, Sendable, Equatable {
  /// The protected resource's resource identifier.
  public let resource: URL

  /// JSON array of OAuth 2.0 authorization server issuer identifiers.
  public let authorizationServers: [String]?

  /// JSON array of supported OAuth 2.0 scope values.
  public let scopesSupported: [String]?

  enum CodingKeys: String, CodingKey {
    case resource
    case authorizationServers = "authorization_servers"
    case scopesSupported = "scopes_supported"
  }
}

/// Errors thrown by OAuthClient.
public enum OAuthClientError: Error, LocalizedError {
  case invalidResourceMetadata
  case noAuthorizationServers
  case invalidAuthorizationServerMetadata
  case missingAuthorizationEndpoint
  case missingTokenEndpoint
  case unsupportedPKCEMethod
  case invalidTokenResponse
  case networkError(Error)
  case randomGenerationFailed
  case invalidState
  case invalidRedirectURI
  case missingRegistrationEndpoint
  case invalidRegistrationResponse
  case registrationFailed(OAuthErrorResponse)
  case invalidClientMetadata

  public var errorDescription: String? {
    switch self {
    case .invalidResourceMetadata:
      return "Invalid resource metadata received from server"
    case .noAuthorizationServers:
      return "No authorization servers found in resource metadata"
    case .invalidAuthorizationServerMetadata:
      return "Invalid authorization server metadata"
    case .missingAuthorizationEndpoint:
      return "Authorization server missing authorization endpoint"
    case .missingTokenEndpoint:
      return "Authorization server missing token endpoint"
    case .unsupportedPKCEMethod:
      return "Server does not support required PKCE code challenge method"
    case .invalidTokenResponse:
      return "Invalid token response from authorization server"
    case .networkError(let error):
      return error.localizedDescription
    case .randomGenerationFailed:
      return "Failed to generate secure random data"
    case .invalidState:
      return "Invalid or mismatched state parameter"
    case .invalidRedirectURI:
      return "Invalid redirect URI"
    case .missingRegistrationEndpoint:
      return "Authorization server does not support dynamic client registration"
    case .invalidRegistrationResponse:
      return "Invalid response from client registration endpoint"
    case .registrationFailed(let error):
      return error.errorDescription ?? "Client registration failed"
    case .invalidClientMetadata:
      return "Invalid client metadata for registration"
    }
  }
}

/// OAuth 2.0 error response as defined in RFC 6749.
public struct OAuthErrorResponse: Error, Codable, Sendable, LocalizedError {
  /// A single ASCII error code from the specification.
  public let error: String

  /// Human-readable ASCII text providing additional information.
  public let errorDescriptionValue: String?

  /// A URI identifying a human-readable web page with error information.
  public let errorUri: String?

  enum CodingKeys: String, CodingKey {
    case error
    case errorDescriptionValue = "error_description"
    case errorUri = "error_uri"
  }

  public var errorDescription: String? {
    if let description = errorDescriptionValue {
      return "\(error): \(description)"
    }
    return error
  }
}

/// OAuth 2.0 Dynamic Client Registration Request as defined in RFC 7591.
public struct ClientRegistrationRequest: Codable, Sendable {
  /// Array of redirection URIs for use in redirect-based flows.
  public let redirectUris: [String]?

  /// Human-readable name of the client to be presented to the end-user.
  public let clientName: String?

  /// Space-separated list of OAuth 2.0 scope values.
  public let scope: String?

  /// Array of OAuth 2.0 grant type strings that the client can use.
  public let grantTypes: [String]?

  /// Array of OAuth 2.0 response type strings that the client can use.
  public let responseTypes: [String]?

  /// Requested authentication method for the token endpoint.
  public let tokenEndpointAuthMethod: String?

  /// Software identifier for the client software.
  public let softwareId: String?

  /// Version identifier for the client software.
  public let softwareVersion: String?

  enum CodingKeys: String, CodingKey {
    case redirectUris = "redirect_uris"
    case clientName = "client_name"
    case scope
    case grantTypes = "grant_types"
    case responseTypes = "response_types"
    case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    case softwareId = "software_id"
    case softwareVersion = "software_version"
  }

  public init(
    redirectUris: [String]? = nil,
    clientName: String? = nil,
    scope: String? = nil,
    grantTypes: [String]? = nil,
    responseTypes: [String]? = nil,
    tokenEndpointAuthMethod: String? = nil,
    softwareId: String? = nil,
    softwareVersion: String? = nil
  ) {
    self.redirectUris = redirectUris
    self.clientName = clientName
    self.scope = scope
    self.grantTypes = grantTypes
    self.responseTypes = responseTypes
    self.tokenEndpointAuthMethod = tokenEndpointAuthMethod
    self.softwareId = softwareId
    self.softwareVersion = softwareVersion
  }
}

/// OAuth 2.0 Dynamic Client Registration Response as defined in RFC 7591.
public struct ClientRegistrationResponse: Codable, Sendable {
  /// Unique client identifier.
  public let clientId: String

  /// Client secret (for confidential clients).
  public let clientSecret: String?

  /// Time at which the client identifier was issued.
  public let clientIdIssuedAt: Int?

  /// Time at which the client secret will expire (0 = no expiration).
  public let clientSecretExpiresAt: Int?

  /// All registered metadata about the client.
  public let redirectUris: [String]?
  public let clientName: String?
  public let scope: String?
  public let grantTypes: [String]?
  public let responseTypes: [String]?
  public let tokenEndpointAuthMethod: String?
  public let softwareId: String?
  public let softwareVersion: String?

  enum CodingKeys: String, CodingKey {
    case clientId = "client_id"
    case clientSecret = "client_secret"
    case clientIdIssuedAt = "client_id_issued_at"
    case clientSecretExpiresAt = "client_secret_expires_at"
    case redirectUris = "redirect_uris"
    case clientName = "client_name"
    case scope
    case grantTypes = "grant_types"
    case responseTypes = "response_types"
    case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    case softwareId = "software_id"
    case softwareVersion = "software_version"
  }
}


/// OAuth 2.0 client implementing authorization code flow with PKCE.
public actor OAuthClient {
  private let urlSession: URLSession
  private let logger: Logger

  /// State parameter for CSRF protection.
  public struct StateParameter: Sendable, Equatable {
    public let value: String
    public let expiresAt: Date

    /// Generates a cryptographically secure state parameter.
    public static func generate() throws -> StateParameter {
      var bytes = [UInt8](repeating: 0, count: 32)
      let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

      guard result == errSecSuccess else {
        throw OAuthClientError.randomGenerationFailed
      }

      let value = Data(bytes).base64URLEncodedString()
      // State parameters expire after 10 minutes
      let expiresAt = Date().addingTimeInterval(600)

      return StateParameter(value: value, expiresAt: expiresAt)
    }

    /// Checks if the state parameter has expired.
    public var isExpired: Bool {
      Date() >= expiresAt
    }
  }

  public init(
    urlSession: URLSession? = nil,
    logger: Logger = Logger(subsystem: "com.indragie.Context", category: "OAuthClient")
  ) {
    // Configure URLSession with stricter security settings
    if let urlSession = urlSession {
      self.urlSession = urlSession
    } else {
      let configuration = URLSessionConfiguration.default
      configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
      configuration.urlCache = nil  // Disable caching for sensitive data
      configuration.httpShouldSetCookies = false
      configuration.httpCookieAcceptPolicy = .never
      self.urlSession = URLSession(configuration: configuration)
    }
    self.logger = logger
  }

  /// PKCE (Proof Key for Code Exchange) parameters.
  public struct PKCEParameters: Sendable, Equatable {
    /// The code verifier - a cryptographically random string.
    public let verifier: String

    /// The code challenge - derived from the verifier.
    public let challenge: String

    /// The method used to derive the challenge (always "S256" for security).
    public let method: String = "S256"

    /// Generates new PKCE parameters with a secure random verifier.
    /// - Throws: If random number generation fails
    public static func generate() throws -> PKCEParameters {
      // OAuth 2.1 requires code_verifier to be 43-128 characters
      // Using 64 bytes = 86 base64url characters for enhanced security
      var bytes = [UInt8](repeating: 0, count: 64)
      let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

      guard result == errSecSuccess else {
        throw OAuthClientError.randomGenerationFailed
      }

      // Base64URL encode without padding
      let verifier = Data(bytes).base64URLEncodedString()

      // Generate challenge using SHA256
      let challengeData = SHA256.hash(data: verifier.data(using: .utf8)!)
      let challenge = Data(challengeData).base64URLEncodedString()

      return PKCEParameters(verifier: verifier, challenge: challenge)
    }
  }

  /// Constructs default authorization server metadata when discovery fails.
  /// This was originally supported in protocol version 2025-03-26 but removed
  /// in protocol version 2025-06-18 -- we support this for backward compatibility.
  ///
  /// - Parameter authServerURL: The base URL of the authorization server.
  /// - Returns: Authorization server metadata with default endpoint paths.
  private func constructDefaultAuthServerMetadata(from authServerURL: URL)
    -> AuthorizationServerMetadata
  {
    // Get the base URL (scheme + host + port if present)
    var components = URLComponents(url: authServerURL, resolvingAgainstBaseURL: false)!
    components.path = ""
    components.query = nil
    components.fragment = nil

    guard let baseURL = components.url else {
      // Fallback to the original URL if we can't construct components
      let baseURL = authServerURL
      return AuthorizationServerMetadata(
        issuer: baseURL.absoluteString,
        authorizationEndpoint: baseURL.appendingPathComponent("authorize"),
        tokenEndpoint: baseURL.appendingPathComponent("token"),
        responseTypesSupported: ["code"],
        grantTypesSupported: ["authorization_code", "refresh_token"],
        codeChallengeMethodsSupported: ["S256"],
        registrationEndpoint: baseURL.appendingPathComponent("register")
      )
    }

    return AuthorizationServerMetadata(
      issuer: baseURL.absoluteString,
      authorizationEndpoint: baseURL.appendingPathComponent("authorize"),
      tokenEndpoint: baseURL.appendingPathComponent("token"),
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code", "refresh_token"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: baseURL.appendingPathComponent("register")
    )
  }

  /// Discovers OAuth metadata for a protected resource.
  ///
  /// - Parameter resourceMetadataURL: The URL of the protected resource metadata endpoint.
  /// - Returns: A tuple containing the optional resource metadata and authorization server metadata.
  ///            Resource metadata will be nil if the server returns 404, indicating older protocol version.
  public func discoverMetadata(resourceMetadataURL: URL) async throws -> (
    resource: ProtectedResourceMetadata?,
    authServer: AuthorizationServerMetadata
  ) {

    logger.info("Discovering OAuth metadata")
    logger.info("Resource metadata URL: \(resourceMetadataURL)")

    // Fetch protected resource metadata
    let resourceMetadata: ProtectedResourceMetadata?
    let authServerIssuer: String

    // Create request with MCP-Protocol-Version header
    var resourceRequest = URLRequest(url: resourceMetadataURL)
    resourceRequest.setValue(MCPProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")

    let (data, response) = try await urlSession.data(for: resourceRequest)

    if let httpResponse = response as? HTTPURLResponse {
      if httpResponse.statusCode == 404 {
        logger.info("Resource metadata endpoint returned 404, using default authorization base URL")
        resourceMetadata = nil

        // Determine authorization base URL by removing path component from resource metadata URL
        var components = URLComponents(url: resourceMetadataURL, resolvingAgainstBaseURL: false)!
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let baseURL = components.url else {
          throw OAuthClientError.invalidResourceMetadata
        }

        authServerIssuer = baseURL.absoluteString
      } else if httpResponse.statusCode == 200 {
        do {
          let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: data)
          resourceMetadata = metadata

          // Get the first authorization server from resource metadata
          guard let issuer = metadata.authorizationServers?.first else {
            throw OAuthClientError.noAuthorizationServers
          }
          authServerIssuer = issuer
        } catch {
          logger.error("Failed to decode resource metadata")
          throw OAuthClientError.invalidResourceMetadata
        }
      } else {
        logger.error("Unexpected response status code: \(httpResponse.statusCode)")
        throw OAuthClientError.invalidResourceMetadata
      }
    } else {
      throw OAuthClientError.invalidResourceMetadata
    }

    // Construct authorization server metadata URL
    guard let authServerURL = URL(string: authServerIssuer) else {
      throw OAuthClientError.invalidAuthorizationServerMetadata
    }


    let authServerMetadataURL = authServerURL.appendingPathComponent(
      ".well-known/oauth-authorization-server")

    // Fetch authorization server metadata
    let authServerMetadata: AuthorizationServerMetadata

    var request = URLRequest(url: authServerMetadataURL)
    request.httpMethod = "GET"
    request.setValue(MCPProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")

    do {
      let (data, response) = try await urlSession.data(for: request)

      // Check if we got a 404 response
      if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode == 404 {
          logger.info(
            "Authorization server metadata not found (404), falling back to default endpoints")
          authServerMetadata = constructDefaultAuthServerMetadata(from: authServerURL)
        } else if httpResponse.statusCode == 200 {
          logger.info("Got 200 response, decoding authorization server metadata")
          do {
            authServerMetadata = try JSONDecoder().decode(
              AuthorizationServerMetadata.self, from: data)
            logger.info("Successfully decoded metadata")
          } catch {
            logger.error("Failed to decode authorization server metadata")
            throw error
          }
        } else {
          logger.error("Unexpected response status code: \(httpResponse.statusCode)")
          throw OAuthClientError.invalidAuthorizationServerMetadata
        }
      } else {
        logger.error("Response is not an HTTP response")
        throw OAuthClientError.invalidAuthorizationServerMetadata
      }
    } catch let error {
      logger.error("Failed to fetch authorization server metadata")
      // If resource metadata was nil (404) and auth server metadata also fails, return defaults
      if resourceMetadata == nil {
        logger.info("Both resource and auth server metadata unavailable, using default endpoints")
        authServerMetadata = constructDefaultAuthServerMetadata(from: authServerURL)
      } else {
        throw OAuthClientError.networkError(error)
      }
    }

    return (resourceMetadata, authServerMetadata)
  }

  /// Constructs the authorization URL for the OAuth flow.
  ///
  /// - Parameters:
  ///   - authServerMetadata: The authorization server metadata.
  ///   - clientID: The OAuth client ID.
  ///   - redirectURI: The redirect URI for the OAuth callback.
  ///   - pkce: The PKCE parameters.
  ///   - state: Optional state parameter for CSRF protection.
  ///   - resource: The resource URL being accessed. Optional for older protocol versions.
  /// - Returns: The authorization URL to open in a browser.
  public nonisolated func buildAuthorizationURL(
    authServerMetadata: AuthorizationServerMetadata,
    clientID: String,
    redirectURI: String,
    pkce: PKCEParameters,
    state: StateParameter,
    resource: URL?
  ) throws -> URL {
    guard let authEndpoint = authServerMetadata.authorizationEndpoint else {
      throw OAuthClientError.missingAuthorizationEndpoint
    }


    guard URL(string: redirectURI) != nil else {
      throw OAuthClientError.invalidRedirectURI
    }

    let supportsS256 = authServerMetadata.codeChallengeMethodsSupported?.contains("S256") ?? true
    guard supportsS256 else {
      throw OAuthClientError.unsupportedPKCEMethod
    }

    var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
    var queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "code_challenge", value: pkce.challenge),
      URLQueryItem(name: "code_challenge_method", value: pkce.method),
    ]

    if let resource = resource {
      queryItems.append(URLQueryItem(name: "resource", value: resource.absoluteString))
    }

    queryItems.append(URLQueryItem(name: "state", value: state.value))

    components.queryItems = queryItems

    guard let url = components.url else {
      throw OAuthClientError.invalidAuthorizationServerMetadata
    }

    return url
  }

  /// Validates that a received state parameter matches the expected value.
  ///
  /// - Parameters:
  ///   - receivedState: The state parameter received from the authorization server.
  ///   - expectedState: The state parameter sent in the authorization request.
  /// - Throws: OAuthClientError.invalidState if validation fails.
  public nonisolated func validateState(received: String?, expected: StateParameter) throws {
    guard let receivedState = received else {
      throw OAuthClientError.invalidState
    }

    guard !expected.isExpired else {
      throw OAuthClientError.invalidState
    }

    // Constant-time comparison to prevent timing attacks
    guard receivedState.count == expected.value.count else {
      throw OAuthClientError.invalidState
    }

    var equal = true
    for (a, b) in zip(receivedState.utf8, expected.value.utf8) {
      equal = equal && (a == b)
    }

    guard equal else {
      throw OAuthClientError.invalidState
    }
  }

  /// Exchanges an authorization code for tokens.
  ///
  /// - Parameters:
  ///   - code: The authorization code received from the authorization server.
  ///   - authServerMetadata: The authorization server metadata.
  ///   - clientID: The OAuth client ID.
  ///   - redirectURI: The redirect URI used in the authorization request.
  ///   - pkce: The PKCE parameters used in the authorization request.
  ///   - resource: The resource URL being accessed. Optional for older protocol versions.
  /// - Returns: The OAuth token response.
  public func exchangeCodeForToken(
    code: String,
    authServerMetadata: AuthorizationServerMetadata,
    clientID: String,
    redirectURI: String,
    pkce: PKCEParameters,
    resource: URL?
  ) async throws -> OAuthToken {
    guard let tokenEndpoint = authServerMetadata.tokenEndpoint else {
      throw OAuthClientError.missingTokenEndpoint
    }


    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(MCPProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")

    var bodyComponents = URLComponents()
    var queryItems = [
      URLQueryItem(name: "grant_type", value: "authorization_code"),
      URLQueryItem(name: "code", value: code),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "code_verifier", value: pkce.verifier),
    ]

    if let resource = resource {
      queryItems.append(URLQueryItem(name: "resource", value: resource.absoluteString))
    }

    bodyComponents.queryItems = queryItems

    request.httpBody = bodyComponents.query?.data(using: .utf8)

    // Log the request details for debugging (without exposing sensitive code/verifier)
    logger.info("Token exchange request to: \(tokenEndpoint.absoluteString)")
    logger.info(
      "Request parameters: grant_type=authorization_code, client_id=\(clientID), redirect_uri=\(redirectURI), resource=\(resource?.absoluteString ?? "nil")"
    )

    do {
      let (data, response) = try await urlSession.data(for: request)

      // Log response details for debugging
      if let httpResponse = response as? HTTPURLResponse {
        logger.info("Token exchange response status: \(httpResponse.statusCode)")

        // Handle both success and error responses
        if httpResponse.statusCode == 200 {
          // Try to decode the token
          do {
            let token = try JSONDecoder().decode(OAuthToken.self, from: data)
            // Log success without exposing sensitive data
            logger.info("Successfully exchanged authorization code for token")
            return token
          } catch let decodingError {
            // Log decoding failure without exposing response content
            logger.error("Failed to decode token response")
            throw OAuthClientError.networkError(decodingError)
          }
        } else {
          // Try to decode as an error response first
          if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            logger.error(
              "Token exchange failed with OAuth error: \(errorResponse.error) - \(errorResponse.errorDescriptionValue ?? "no description")"
            )
            throw errorResponse
          } else {
            logger.error("Token exchange failed with status \(httpResponse.statusCode)")
          }
          throw OAuthClientError.invalidTokenResponse
        }
      } else {
        throw OAuthClientError.invalidTokenResponse
      }
    } catch {
      // Don't wrap errors that are already OAuthErrorResponse
      if error is OAuthErrorResponse {
        throw error
      }
      logger.error("Failed to exchange code for token")
      throw OAuthClientError.networkError(error)
    }
  }

  /// Refreshes an access token using a refresh token.
  ///
  /// - Parameters:
  ///   - refreshToken: The refresh token.
  ///   - authServerMetadata: The authorization server metadata.
  ///   - clientID: The OAuth client ID.
  ///   - resource: The resource URL being accessed. Optional for older protocol versions.
  /// - Returns: The new OAuth token.
  public func refreshToken(
    refreshToken: String,
    authServerMetadata: AuthorizationServerMetadata,
    clientID: String,
    resource: URL?
  ) async throws -> OAuthToken {
    guard let tokenEndpoint = authServerMetadata.tokenEndpoint else {
      throw OAuthClientError.missingTokenEndpoint
    }


    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(MCPProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")

    var bodyComponents = URLComponents()
    var queryItems = [
      URLQueryItem(name: "grant_type", value: "refresh_token"),
      URLQueryItem(name: "refresh_token", value: refreshToken),
      URLQueryItem(name: "client_id", value: clientID),
    ]

    if let resource = resource {
      queryItems.append(URLQueryItem(name: "resource", value: resource.absoluteString))
    }

    bodyComponents.queryItems = queryItems

    request.httpBody = bodyComponents.query?.data(using: .utf8)

    do {
      let (data, response) = try await urlSession.data(for: request)

      if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode == 200 {
          let token = try JSONDecoder().decode(OAuthToken.self, from: data)
          logger.info("Successfully refreshed token")
          return token
        } else {
          // Try to decode as an error response
          if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            logger.error(
              "Token refresh failed with OAuth error: \(errorResponse.error) - \(errorResponse.errorDescriptionValue ?? "no description")"
            )
            throw errorResponse
          }
          throw OAuthClientError.invalidTokenResponse
        }
      } else {
        throw OAuthClientError.invalidTokenResponse
      }
    } catch {
      if error is OAuthErrorResponse {
        throw error
      }
      logger.error("Failed to refresh token")
      throw OAuthClientError.networkError(error)
    }
  }

  /// Performs dynamic client registration according to RFC 7591.
  ///
  /// - Parameters:
  ///   - authServerMetadata: The authorization server metadata containing the registration endpoint.
  ///   - registrationRequest: The client registration request with desired client metadata.
  /// - Returns: The client registration response containing the assigned client_id and other metadata.
  /// - Throws: OAuthClientError if registration fails or is not supported.
  public func registerClient(
    authServerMetadata: AuthorizationServerMetadata,
    registrationRequest: ClientRegistrationRequest
  ) async throws -> ClientRegistrationResponse {
    // Check if registration endpoint is available
    guard let registrationEndpoint = authServerMetadata.registrationEndpoint else {
      throw OAuthClientError.missingRegistrationEndpoint
    }


    // Validate redirect URIs in the request
    if let redirectUris = registrationRequest.redirectUris {
      for uri in redirectUris {
        guard URL(string: uri) != nil else {
          throw OAuthClientError.invalidClientMetadata
        }
      }
    }

    // Create the registration request
    var request = URLRequest(url: registrationEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(MCPProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")

    // Encode the registration request
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    do {
      request.httpBody = try encoder.encode(registrationRequest)
    } catch {
      logger.error("Failed to encode registration request")
      throw OAuthClientError.invalidClientMetadata
    }

    // Log registration attempt (without sensitive data)
    logger.info("Attempting dynamic client registration at: \(registrationEndpoint.absoluteString)")
    if let clientName = registrationRequest.clientName {
      logger.info("Registering client: \(clientName)")
    }

    do {
      let (data, response) = try await urlSession.data(for: request)

      if let httpResponse = response as? HTTPURLResponse {
        logger.info("Registration response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 201:
          // Success - parse the registration response
          do {
            let registrationResponse = try JSONDecoder().decode(
              ClientRegistrationResponse.self, from: data)
            logger.info("Successfully registered client with ID: \(registrationResponse.clientId)")
            return registrationResponse
          } catch {
            logger.error("Failed to decode registration response")
            throw OAuthClientError.invalidRegistrationResponse
          }

        case 400:
          // Bad request - try to decode error response
          if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            logger.error(
              "Registration failed with error: \(errorResponse.error) - \(errorResponse.errorDescriptionValue ?? "no description")"
            )
            throw OAuthClientError.registrationFailed(errorResponse)
          } else {
            logger.error("Registration failed with status 400")
          }
          throw OAuthClientError.invalidRegistrationResponse

        default:
          // Other error status codes
          if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            logger.error(
              "Registration failed with error: \(errorResponse.error) - \(errorResponse.errorDescriptionValue ?? "no description")"
            )
            throw OAuthClientError.registrationFailed(errorResponse)
          } else {
            logger.error("Registration failed with status \(httpResponse.statusCode)")
          }
          throw OAuthClientError.invalidRegistrationResponse
        }
      } else {
        throw OAuthClientError.invalidRegistrationResponse
      }
    } catch {
      // Don't wrap errors that are already OAuthClientError
      if error is OAuthClientError {
        throw error
      }
      logger.error("Failed to register client")
      throw OAuthClientError.networkError(error)
    }
  }
}

// MARK: - Extensions

extension Data {
  /// Base64URL encodes the data without padding.
  fileprivate func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
