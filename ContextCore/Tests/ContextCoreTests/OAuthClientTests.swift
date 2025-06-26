// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

// Test errors
enum TestError: Error, LocalizedError {
  case noRequestHandler
  case unexpectedURL(String)

  var errorDescription: String? {
    switch self {
    case .noRequestHandler:
      return "No request handler configured for mock URL protocol"
    case .unexpectedURL(let url):
      return "Unexpected URL: \(url)"
    }
  }
}

// Mock URLProtocol to intercept network requests
class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

  override class func canInit(with request: URLRequest) -> Bool {
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let handler = MockURLProtocol.requestHandler else {
      client?.urlProtocol(self, didFailWithError: TestError.noRequestHandler)
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      if let data = data {
        client?.urlProtocol(self, didLoad: data)
      }
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {
    // Nothing to do
  }
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct OAuthClientTests {

  // Creates a URLSession configured with MockURLProtocol
  func createMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }

  @Test func testDiscoverMetadataWithFallback() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let resourceMetadataURL = URL(string: "https://example.com/.well-known/mcp-resource")!
    let authServerURL = "https://auth.example.com"

    // Set up mock responses
    MockURLProtocol.requestHandler = { request in
      switch request.url?.absoluteString {
      case "https://example.com/.well-known/mcp-resource":
        // Return valid resource metadata
        let resourceMetadata = ProtectedResourceMetadata(
          resource: URL(string: "https://example.com/resource")!,
          authorizationServers: [authServerURL],
          scopesSupported: ["read", "write"]
        )
        let data = try JSONEncoder().encode(resourceMetadata)
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)

      case "https://auth.example.com/.well-known/oauth-authorization-server":
        // Return 404 to trigger fallback
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 404,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, nil)

      default:
        throw TestError.unexpectedURL(request.url?.absoluteString ?? "nil")
      }
    }

    // Call discoverMetadata
    let (resourceMetadata, authServerMetadata) = try await client.discoverMetadata(
      resourceMetadataURL: resourceMetadataURL
    )

    // Verify resource metadata
    #expect(resourceMetadata?.resource.absoluteString == "https://example.com/resource")
    #expect(resourceMetadata?.authorizationServers?.first == authServerURL)

    // Verify fallback authorization server metadata
    #expect(authServerMetadata.issuer == authServerURL)
    #expect(
      authServerMetadata.authorizationEndpoint?.absoluteString
        == "https://auth.example.com/authorize")
    #expect(authServerMetadata.tokenEndpoint?.absoluteString == "https://auth.example.com/token")
    #expect(
      authServerMetadata.registrationEndpoint?.absoluteString == "https://auth.example.com/register"
    )
    #expect(authServerMetadata.responseTypesSupported == ["code"])
    #expect(authServerMetadata.grantTypesSupported == ["authorization_code", "refresh_token"])
    #expect(authServerMetadata.codeChallengeMethodsSupported == ["S256"])

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testDiscoverMetadataWithValidMetadata() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let resourceMetadataURL = URL(string: "https://example.com/.well-known/mcp-resource")!
    let authServerURL = "https://auth.example.com"

    // Set up mock responses
    MockURLProtocol.requestHandler = { request in
      switch request.url?.absoluteString {
      case "https://example.com/.well-known/mcp-resource":
        // Return valid resource metadata
        let resourceMetadata = ProtectedResourceMetadata(
          resource: URL(string: "https://example.com/resource")!,
          authorizationServers: [authServerURL],
          scopesSupported: ["read", "write"]
        )
        let data = try JSONEncoder().encode(resourceMetadata)
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)

      case "https://auth.example.com/.well-known/oauth-authorization-server":
        // Return valid authorization server metadata
        let authMetadata = AuthorizationServerMetadata(
          issuer: authServerURL,
          authorizationEndpoint: URL(string: "https://auth.example.com/oauth/authorize")!,
          tokenEndpoint: URL(string: "https://auth.example.com/oauth/token")!,
          responseTypesSupported: ["code", "token"],
          grantTypesSupported: ["authorization_code", "refresh_token", "client_credentials"],
          codeChallengeMethodsSupported: ["S256", "plain"],
          registrationEndpoint: URL(string: "https://auth.example.com/oauth/register")!
        )
        let data = try JSONEncoder().encode(authMetadata)
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)

      default:
        throw TestError.unexpectedURL(request.url?.absoluteString ?? "nil")
      }
    }

    // Call discoverMetadata
    let (resourceMetadata, authServerMetadata) = try await client.discoverMetadata(
      resourceMetadataURL: resourceMetadataURL
    )

    // Verify resource metadata
    #expect(resourceMetadata?.resource.absoluteString == "https://example.com/resource")
    #expect(resourceMetadata?.authorizationServers?.first == authServerURL)

    // Verify authorization server metadata (should use discovered values, not fallbacks)
    #expect(authServerMetadata.issuer == authServerURL)
    #expect(
      authServerMetadata.authorizationEndpoint?.absoluteString
        == "https://auth.example.com/oauth/authorize")
    #expect(
      authServerMetadata.tokenEndpoint?.absoluteString == "https://auth.example.com/oauth/token")
    #expect(
      authServerMetadata.registrationEndpoint?.absoluteString
        == "https://auth.example.com/oauth/register")
    #expect(authServerMetadata.responseTypesSupported == ["code", "token"])
    #expect(
      authServerMetadata.grantTypesSupported == [
        "authorization_code", "refresh_token", "client_credentials",
      ])
    #expect(authServerMetadata.codeChallengeMethodsSupported == ["S256", "plain"])

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testDiscoverMetadataWith404ResourceMetadata() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let resourceMetadataURL = URL(string: "https://api.example.com/v1/.well-known/mcp-resource")!

    // Set up mock responses
    MockURLProtocol.requestHandler = { request in
      switch request.url?.absoluteString {
      case "https://api.example.com/v1/.well-known/mcp-resource":
        // Return 404 for resource metadata
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 404,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())

      case "https://api.example.com/.well-known/oauth-authorization-server":
        // Also return 404 for auth server metadata to test double fallback
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 404,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())

      default:
        throw TestError.unexpectedURL(request.url?.absoluteString ?? "nil")
      }
    }

    // Call discoverMetadata
    let (resourceMetadata, authServerMetadata) = try await client.discoverMetadata(
      resourceMetadataURL: resourceMetadataURL
    )

    // Verify resource metadata is nil
    #expect(resourceMetadata == nil)

    // Verify authorization server metadata uses default endpoints based on base URL
    #expect(authServerMetadata.issuer == "https://api.example.com")
    #expect(
      authServerMetadata.authorizationEndpoint?.absoluteString
        == "https://api.example.com/authorize")
    #expect(authServerMetadata.tokenEndpoint?.absoluteString == "https://api.example.com/token")
    #expect(
      authServerMetadata.registrationEndpoint?.absoluteString == "https://api.example.com/register")
    #expect(authServerMetadata.responseTypesSupported == ["code"])
    #expect(authServerMetadata.grantTypesSupported == ["authorization_code", "refresh_token"])
    #expect(authServerMetadata.codeChallengeMethodsSupported == ["S256"])

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testDiscoverMetadataWith404ResourceButValidAuthServer() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let resourceMetadataURL = URL(string: "https://api.example.com/v1/.well-known/mcp-resource")!

    // Set up mock responses
    MockURLProtocol.requestHandler = { request in
      switch request.url?.absoluteString {
      case "https://api.example.com/v1/.well-known/mcp-resource":
        // Return 404 for resource metadata
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 404,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())

      case "https://api.example.com/.well-known/oauth-authorization-server":
        // Return valid authorization server metadata
        let authMetadata = AuthorizationServerMetadata(
          issuer: "https://api.example.com",
          authorizationEndpoint: URL(string: "https://api.example.com/oauth/authorize")!,
          tokenEndpoint: URL(string: "https://api.example.com/oauth/token")!,
          responseTypesSupported: ["code", "token"],
          grantTypesSupported: ["authorization_code", "refresh_token"],
          codeChallengeMethodsSupported: ["S256"],
          registrationEndpoint: URL(string: "https://api.example.com/oauth/register")!
        )
        let data = try JSONEncoder().encode(authMetadata)
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)

      default:
        throw TestError.unexpectedURL(request.url?.absoluteString ?? "nil")
      }
    }

    // Call discoverMetadata
    let (resourceMetadata, authServerMetadata) = try await client.discoverMetadata(
      resourceMetadataURL: resourceMetadataURL
    )

    // Verify resource metadata is nil
    #expect(resourceMetadata == nil)

    // Verify authorization server metadata uses discovered values (not defaults)
    #expect(authServerMetadata.issuer == "https://api.example.com")
    #expect(
      authServerMetadata.authorizationEndpoint?.absoluteString
        == "https://api.example.com/oauth/authorize")
    #expect(
      authServerMetadata.tokenEndpoint?.absoluteString == "https://api.example.com/oauth/token")
    #expect(
      authServerMetadata.registrationEndpoint?.absoluteString
        == "https://api.example.com/oauth/register")
    #expect(authServerMetadata.responseTypesSupported == ["code", "token"])
    #expect(authServerMetadata.grantTypesSupported == ["authorization_code", "refresh_token"])
    #expect(authServerMetadata.codeChallengeMethodsSupported == ["S256"])

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testTokenExchangeWithErrorResponse() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let authServerMetadata = AuthorizationServerMetadata(
      issuer: "https://auth.example.com",
      authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
      tokenEndpoint: URL(string: "https://auth.example.com/token")!,
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: nil
    )

    let pkce = try OAuthClient.PKCEParameters.generate()

    // Set up mock to return an OAuth error response
    MockURLProtocol.requestHandler = { request in
      #expect(request.url?.absoluteString == "https://auth.example.com/token")
      #expect(request.httpMethod == "POST")
      #expect(
        request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
      #expect(request.value(forHTTPHeaderField: "MCP-Protocol-Version") == MCPProtocolVersion)

      let errorResponse = OAuthErrorResponse(
        error: "invalid_grant",
        errorDescriptionValue: "The provided authorization grant is invalid, expired, revoked",
        errorUri: nil
      )
      let data = try JSONEncoder().encode(errorResponse)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 400,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, data)
    }

    // Test token exchange with error response
    do {
      _ = try await client.exchangeCodeForToken(
        code: "invalid_code",
        authServerMetadata: authServerMetadata,
        clientID: "test_client",
        redirectURI: "context://oauth/callback",
        pkce: pkce,
        resource: nil
      )
      #expect(Bool(false), "Should have thrown an error")
    } catch let error as OAuthErrorResponse {
      #expect(error.error == "invalid_grant")
      #expect(
        error.errorDescriptionValue
          == "The provided authorization grant is invalid, expired, revoked")
    } catch {
      #expect(Bool(false), "Should have thrown OAuthErrorResponse, but threw: \(error)")
    }

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testTokenExchangeWithMissingAccessToken() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let authServerMetadata = AuthorizationServerMetadata(
      issuer: "https://auth.example.com",
      authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
      tokenEndpoint: URL(string: "https://auth.example.com/token")!,
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: nil
    )

    let pkce = try OAuthClient.PKCEParameters.generate()

    // Set up mock to return a response missing access_token
    MockURLProtocol.requestHandler = { request in
      #expect(request.url?.absoluteString == "https://auth.example.com/token")

      // Return a response that's missing the access_token field
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      let data = "{\"token_type\":\"Bearer\",\"expires_in\":3600}".data(using: .utf8)!
      return (response, data)
    }

    // Test token exchange with missing access_token
    do {
      _ = try await client.exchangeCodeForToken(
        code: "valid_code",
        authServerMetadata: authServerMetadata,
        clientID: "test_client",
        redirectURI: "context://oauth/callback",
        pkce: pkce,
        resource: nil
      )
      #expect(Bool(false), "Should have thrown an error")
    } catch let error as OAuthClientError {
      if case .networkError = error {
        // Expected error when decoding fails
      } else {
        #expect(Bool(false), "Should have thrown networkError, but threw: \(error)")
      }
    } catch {
      #expect(Bool(false), "Should have thrown OAuthClientError, but threw: \(error)")
    }

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testTokenExchangeWithThirdPartyFlow() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let authServerMetadata = AuthorizationServerMetadata(
      issuer: "https://mcp.example.com",
      authorizationEndpoint: URL(string: "https://mcp.example.com/authorize")!,
      tokenEndpoint: URL(string: "https://mcp.example.com/token")!,
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: nil
    )

    let pkce = try OAuthClient.PKCEParameters.generate()

    // Set up mock to simulate successful third-party flow
    MockURLProtocol.requestHandler = { request in
      #expect(request.url?.absoluteString == "https://mcp.example.com/token")

      // Return a valid token response
      let tokenData = """
        {
          "access_token": "mcp_access_token_123",
          "token_type": "Bearer",
          "expires_in": 3600,
          "refresh_token": "mcp_refresh_token_456"
        }
        """.data(using: .utf8)!
      let data = tokenData
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, data)
    }

    // Test successful token exchange in third-party flow
    let token = try await client.exchangeCodeForToken(
      code: "auth_code_from_third_party",
      authServerMetadata: authServerMetadata,
      clientID: "com.indragie.Context",
      redirectURI: "context://oauth/callback",
      pkce: pkce,
      resource: URL(string: "https://mcp.example.com/api")!
    )

    #expect(token.accessToken == "mcp_access_token_123")
    #expect(token.tokenType == "Bearer")
    #expect(token.refreshToken == "mcp_refresh_token_456")

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  // MARK: - Dynamic Client Registration Tests

  @Test func testSuccessfulClientRegistration() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let authServerMetadata = AuthorizationServerMetadata(
      issuer: "https://auth.example.com",
      authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
      tokenEndpoint: URL(string: "https://auth.example.com/token")!,
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code", "refresh_token"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: URL(string: "https://auth.example.com/register")!
    )

    let registrationRequest = ClientRegistrationRequest(
      redirectUris: ["context://oauth/callback"],
      clientName: "Context MCP Client",
      scope: "read write",
      grantTypes: ["authorization_code", "refresh_token"],
      responseTypes: ["code"],
      tokenEndpointAuthMethod: "none",
      softwareId: "com.indragie.Context",
      softwareVersion: "1.0.0"
    )

    // Set up mock to return successful registration response
    MockURLProtocol.requestHandler = { request in
      #expect(request.url?.absoluteString == "https://auth.example.com/register")
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      #expect(request.value(forHTTPHeaderField: "MCP-Protocol-Version") == MCPProtocolVersion)

      // Verify request body
      if let body = request.httpBody {
        let decodedRequest = try JSONDecoder().decode(ClientRegistrationRequest.self, from: body)
        #expect(decodedRequest.redirectUris == ["context://oauth/callback"])
        #expect(decodedRequest.clientName == "Context MCP Client")
      }

      let responseData = """
        {
          "client_id": "dynamic_client_id_123",
          "client_secret": null,
          "client_id_issued_at": 1234567890,
          "redirect_uris": ["context://oauth/callback"],
          "client_name": "Context MCP Client",
          "scope": "read write",
          "grant_types": ["authorization_code", "refresh_token"],
          "response_types": ["code"],
          "token_endpoint_auth_method": "none",
          "software_id": "com.indragie.Context",
          "software_version": "1.0.0"
        }
        """.data(using: .utf8)!

      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 201,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }

    // Test successful registration
    let registrationResponse = try await client.registerClient(
      authServerMetadata: authServerMetadata,
      registrationRequest: registrationRequest
    )

    #expect(registrationResponse.clientId == "dynamic_client_id_123")
    #expect(registrationResponse.clientSecret == nil)
    #expect(registrationResponse.clientIdIssuedAt == 1_234_567_890)
    #expect(registrationResponse.redirectUris == ["context://oauth/callback"])
    #expect(registrationResponse.clientName == "Context MCP Client")
    #expect(registrationResponse.tokenEndpointAuthMethod == "none")

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testClientRegistrationWithInvalidRedirectUri() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let authServerMetadata = AuthorizationServerMetadata(
      issuer: "https://auth.example.com",
      authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
      tokenEndpoint: URL(string: "https://auth.example.com/token")!,
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: URL(string: "https://auth.example.com/register")!
    )

    let registrationRequest = ClientRegistrationRequest(
      redirectUris: ["context://oauth/callback", "https://malicious.com/callback"],
      clientName: "Context MCP Client"
    )

    // Set up mock to return error for invalid redirect URI
    MockURLProtocol.requestHandler = { request in
      #expect(request.url?.absoluteString == "https://auth.example.com/register")

      let errorResponse = OAuthErrorResponse(
        error: "invalid_redirect_uri",
        errorDescriptionValue: "Redirect URI https://malicious.com/callback is not allowed",
        errorUri: nil
      )
      let data = try JSONEncoder().encode(errorResponse)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 400,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, data)
    }

    // Test registration with invalid redirect URI
    do {
      _ = try await client.registerClient(
        authServerMetadata: authServerMetadata,
        registrationRequest: registrationRequest
      )
      #expect(Bool(false), "Should have thrown an error")
    } catch let error as OAuthClientError {
      if case .registrationFailed(let oauthError) = error {
        #expect(oauthError.error == "invalid_redirect_uri")
        #expect(oauthError.errorDescriptionValue?.contains("not allowed") == true)
      } else {
        #expect(Bool(false), "Should have thrown registrationFailed error, but threw: \(error)")
      }
    } catch {
      #expect(Bool(false), "Should have thrown OAuthClientError, but threw: \(error)")
    }

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testClientRegistrationWithMissingEndpoint() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    // Authorization server metadata without registration endpoint
    let authServerMetadata = AuthorizationServerMetadata(
      issuer: "https://auth.example.com",
      authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
      tokenEndpoint: URL(string: "https://auth.example.com/token")!,
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: nil  // No registration endpoint
    )

    let registrationRequest = ClientRegistrationRequest(
      redirectUris: ["context://oauth/callback"],
      clientName: "Context MCP Client"
    )

    // Test registration without endpoint
    do {
      _ = try await client.registerClient(
        authServerMetadata: authServerMetadata,
        registrationRequest: registrationRequest
      )
      #expect(Bool(false), "Should have thrown an error")
    } catch let error as OAuthClientError {
      if case .missingRegistrationEndpoint = error {
        // Expected error
      } else {
        #expect(
          Bool(false), "Should have thrown missingRegistrationEndpoint error, but threw: \(error)")
      }
    } catch {
      #expect(Bool(false), "Should have thrown OAuthClientError, but threw: \(error)")
    }
  }

  @Test func testClientRegistrationWithInvalidClientMetadata() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let authServerMetadata = AuthorizationServerMetadata(
      issuer: "https://auth.example.com",
      authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
      tokenEndpoint: URL(string: "https://auth.example.com/token")!,
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: URL(string: "https://auth.example.com/register")!
    )

    let registrationRequest = ClientRegistrationRequest(
      redirectUris: ["context://oauth/callback"],
      clientName: "Context MCP Client",
      grantTypes: ["unsupported_grant_type"]  // Invalid grant type
    )

    // Set up mock to return error for invalid metadata
    MockURLProtocol.requestHandler = { request in
      #expect(request.url?.absoluteString == "https://auth.example.com/register")

      let errorResponse = OAuthErrorResponse(
        error: "invalid_client_metadata",
        errorDescriptionValue: "Grant type 'unsupported_grant_type' is not supported",
        errorUri: nil
      )
      let data = try JSONEncoder().encode(errorResponse)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 400,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, data)
    }

    // Test registration with invalid metadata
    do {
      _ = try await client.registerClient(
        authServerMetadata: authServerMetadata,
        registrationRequest: registrationRequest
      )
      #expect(Bool(false), "Should have thrown an error")
    } catch let error as OAuthClientError {
      if case .registrationFailed(let oauthError) = error {
        #expect(oauthError.error == "invalid_client_metadata")
        #expect(oauthError.errorDescriptionValue?.contains("not supported") == true)
      } else {
        #expect(Bool(false), "Should have thrown registrationFailed error, but threw: \(error)")
      }
    } catch {
      #expect(Bool(false), "Should have thrown OAuthClientError, but threw: \(error)")
    }

    // Clean up
    MockURLProtocol.requestHandler = nil
  }

  @Test func testClientRegistrationWithConfidentialClient() async throws {
    let mockSession = createMockSession()
    let client = OAuthClient(urlSession: mockSession)

    let authServerMetadata = AuthorizationServerMetadata(
      issuer: "https://auth.example.com",
      authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
      tokenEndpoint: URL(string: "https://auth.example.com/token")!,
      responseTypesSupported: ["code"],
      grantTypesSupported: ["authorization_code", "client_credentials"],
      codeChallengeMethodsSupported: ["S256"],
      registrationEndpoint: URL(string: "https://auth.example.com/register")!
    )

    let registrationRequest = ClientRegistrationRequest(
      redirectUris: ["context://oauth/callback"],
      clientName: "Context MCP Client",
      grantTypes: ["authorization_code", "client_credentials"],
      tokenEndpointAuthMethod: "client_secret_basic"  // Requesting confidential client
    )

    // Set up mock to return response with client secret
    MockURLProtocol.requestHandler = { request in
      #expect(request.url?.absoluteString == "https://auth.example.com/register")

      let responseData = """
        {
          "client_id": "confidential_client_456",
          "client_secret": "super_secret_password_789",
          "client_id_issued_at": 1234567890,
          "client_secret_expires_at": 0,
          "redirect_uris": ["context://oauth/callback"],
          "client_name": "Context MCP Client",
          "grant_types": ["authorization_code", "client_credentials"],
          "token_endpoint_auth_method": "client_secret_basic"
        }
        """.data(using: .utf8)!

      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 201,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }

    // Test successful registration of confidential client
    let registrationResponse = try await client.registerClient(
      authServerMetadata: authServerMetadata,
      registrationRequest: registrationRequest
    )

    #expect(registrationResponse.clientId == "confidential_client_456")
    #expect(registrationResponse.clientSecret == "super_secret_password_789")
    #expect(registrationResponse.clientSecretExpiresAt == 0)  // No expiration
    #expect(registrationResponse.tokenEndpointAuthMethod == "client_secret_basic")

    // Clean up
    MockURLProtocol.requestHandler = nil
  }
}
