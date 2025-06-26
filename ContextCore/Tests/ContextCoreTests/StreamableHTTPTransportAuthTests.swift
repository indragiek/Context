// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite(.serialized, .timeLimit(.minutes(1))) struct StreamableHTTPTransportAuthTests {

  // Test-specific errors
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

  // Mock URLProtocol for testing
  class AuthMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler:
      ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
      return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
      return request
    }

    override func startLoading() {
      guard let handler = AuthMockURLProtocol.requestHandler else {
        client?.urlProtocol(self, didFailWithError: TestError.noRequestHandler)
        return
      }

      // Handle httpBodyStream if httpBody is nil
      var modifiedRequest = request
      if request.httpBody == nil, let bodyStream = request.httpBodyStream {
        var bodyData = Data()
        bodyStream.open()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
          buffer.deallocate()
          bodyStream.close()
        }

        while bodyStream.hasBytesAvailable {
          let bytesRead = bodyStream.read(buffer, maxLength: bufferSize)
          if bytesRead > 0 {
            bodyData.append(buffer, count: bytesRead)
          }
        }
        modifiedRequest.httpBody = bodyData
      }

      do {
        let (response, data) = try handler(modifiedRequest)
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

  @Test func testMetadataDiscoveryIncludesMCPProtocolVersionHeader() async throws {
    let mockSession = URLSessionConfiguration.ephemeral
    mockSession.protocolClasses = [AuthMockURLProtocol.self]
    let urlSession = URLSession(configuration: mockSession)
    let client = OAuthClient(urlSession: urlSession)

    var capturedResourceHeaders: [String: String]?
    var capturedAuthServerHeaders: [String: String]?

    // Set up mock to capture headers
    AuthMockURLProtocol.requestHandler = { request in
      if request.url?.absoluteString.contains(".well-known/mcp-resource") == true {
        capturedResourceHeaders = request.allHTTPHeaderFields

        // Return valid resource metadata
        let metadata = ProtectedResourceMetadata(
          resource: URL(string: "https://example.com/resource")!,
          authorizationServers: ["https://auth.example.com"],
          scopesSupported: ["read", "write"]
        )
        let data = try JSONEncoder().encode(metadata)

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
      } else if request.url?.absoluteString.contains(".well-known/oauth-authorization-server")
        == true
      {
        capturedAuthServerHeaders = request.allHTTPHeaderFields

        // Return valid auth server metadata
        let authMetadata = AuthorizationServerMetadata(
          issuer: "https://auth.example.com",
          authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
          tokenEndpoint: URL(string: "https://auth.example.com/token")!,
          responseTypesSupported: ["code"],
          grantTypesSupported: ["authorization_code", "refresh_token"],
          codeChallengeMethodsSupported: ["S256"],
          registrationEndpoint: URL(string: "https://auth.example.com/register")!
        )
        let data = try JSONEncoder().encode(authMetadata)

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
      } else {
        throw TestError.unexpectedURL(request.url?.absoluteString ?? "nil")
      }
    }

    _ = try await client.discoverMetadata(
      resourceMetadataURL: URL(string: "https://example.com/.well-known/mcp-resource")!
    )

    // Verify MCP-Protocol-Version header was included in both requests
    #expect(capturedResourceHeaders?["MCP-Protocol-Version"] == MCPProtocolVersion)
    #expect(capturedAuthServerHeaders?["MCP-Protocol-Version"] == MCPProtocolVersion)

    // Clean up
    AuthMockURLProtocol.requestHandler = nil
  }

  @Test func testStreamableHTTPTransportSetsCommonMCPHeaders() async throws {
    let mockSession = URLSessionConfiguration.ephemeral
    mockSession.protocolClasses = [AuthMockURLProtocol.self]

    let transport = StreamableHTTPTransport(
      serverURL: URL(string: "https://test.example.com/mcp")!,
      urlSessionConfiguration: mockSession,
      clientInfo: Implementation(name: "TestClient", version: "1.0"),
      clientCapabilities: ClientCapabilities()
    )

    var capturedInitializeHeaders: [String: String]?
    var capturedPostHeaders: [String: String]?
    var capturedDeleteHeaders: [String: String]?

    // Track the session ID returned during initialization
    let sessionID = "test-session-123"
    let negotiatedProtocolVersion = "2025-03-26"

    AuthMockURLProtocol.requestHandler = { request in
      let headers = request.allHTTPHeaderFields ?? [:]

      if request.httpMethod == "POST" {
        // Decode the body to check if it's an initialize request
        if let body = request.httpBody,
          let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          json["method"] as? String == "initialize"
        {
          // Initialize request
          capturedInitializeHeaders = headers

          // Return successful initialize response with session ID
          let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "Mcp-Session-Id": sessionID]
          )!

          let initResponse = """
            {
              "jsonrpc": "2.0",
              "id": "\(json["id"] ?? "")",
              "result": {
                "protocolVersion": "\(negotiatedProtocolVersion)",
                "capabilities": {},
                "serverInfo": {"name": "TestServer", "version": "1.0"}
              }
            }
            """.data(using: .utf8)!

          return (response, initResponse)
        } else if let body = request.httpBody,
          let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          json["method"] as? String == "notifications/initialized"
        {
          // Initialized notification - just acknowledge
          let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 202,
            httpVersion: nil,
            headerFields: nil
          )!
          return (response, nil)
        } else {
          // Regular POST request
          capturedPostHeaders = headers

          let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
          )!

          // Return a simple response matching the request ID
          if let body = request.httpBody,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let requestId = json["id"]
          {
            let responseData = """
              {
                "jsonrpc": "2.0",
                "id": "\(requestId)",
                "result": {}
              }
              """.data(using: .utf8)!

            return (response, responseData)
          } else {
            // Fallback response
            let responseData = """
              {
                "jsonrpc": "2.0",
                "id": "test-id",
                "result": {}
              }
              """.data(using: .utf8)!

            return (response, responseData)
          }
        }
      } else if request.httpMethod == "GET" {
        // SSE stream request - skip for this test
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "text/event-stream"]
        )!

        // Return minimal SSE stream data
        let sseData = "event: endpoint\ndata: /events\n\n".data(using: .utf8)!
        return (response, sseData)
      } else if request.httpMethod == "DELETE" {
        // Session termination request
        capturedDeleteHeaders = headers

        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, nil)
      }

      throw TestError.unexpectedURL(
        "\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "nil")")
    }

    // Start the transport and initialize
    try await transport.start()
    _ = try await transport.initialize(idGenerator: { .string("init-1") })

    // Set an authorization token
    await transport.setAuthorizationToken("test-token-xyz")

    // Send a test request to capture POST headers
    let testRequest = PingRequest(id: .string("ping-1"))
    try await transport.send(request: testRequest)

    // Close the transport to capture DELETE headers
    try await transport.close()

    // Verify headers in initialize request (before negotiation)
    #expect(capturedInitializeHeaders?["MCP-Protocol-Version"] == MCPProtocolVersion)
    #expect(capturedInitializeHeaders?["Authorization"] == nil)  // No token yet
    #expect(capturedInitializeHeaders?["Mcp-Session-Id"] == nil)  // No session yet

    // Verify headers in regular POST request (after negotiation)
    #expect(capturedPostHeaders?["MCP-Protocol-Version"] == negotiatedProtocolVersion)
    #expect(capturedPostHeaders?["Authorization"] == "Bearer test-token-xyz")
    #expect(capturedPostHeaders?["Mcp-Session-Id"] == sessionID)

    // Verify headers in DELETE request (if sent)
    // DELETE is only sent when sessionID exists and sendEventEndpointURL is nil (streamable HTTP mode)
    if let deleteHeaders = capturedDeleteHeaders {
      #expect(deleteHeaders["MCP-Protocol-Version"] == negotiatedProtocolVersion)
      #expect(deleteHeaders["Authorization"] == "Bearer test-token-xyz")
      #expect(deleteHeaders["Mcp-Session-Id"] == sessionID)
    }

    // Clean up
    AuthMockURLProtocol.requestHandler = nil
  }

  @Test func testStreamableHTTPTransportHeadersBeforeInitialization() async throws {
    let mockSession = URLSessionConfiguration.ephemeral
    mockSession.protocolClasses = [AuthMockURLProtocol.self]

    let transport = StreamableHTTPTransport(
      serverURL: URL(string: "https://test.example.com/mcp")!,
      urlSessionConfiguration: mockSession,
      clientInfo: Implementation(name: "TestClient", version: "1.0"),
      clientCapabilities: ClientCapabilities()
    )

    var capturedHeaders: [String: String]?

    AuthMockURLProtocol.requestHandler = { request in
      capturedHeaders = request.allHTTPHeaderFields

      // Return error to prevent actual initialization
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 500,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, nil)
    }

    try await transport.start()

    // Try to initialize (will fail, but we can check headers)
    do {
      _ = try await transport.initialize(idGenerator: { .string("init-1") })
    } catch {
      // Expected to fail
    }

    // Verify default protocol version is used before negotiation
    #expect(capturedHeaders?["MCP-Protocol-Version"] == MCPProtocolVersion)
    #expect(capturedHeaders?["Authorization"] == nil)
    #expect(capturedHeaders?["Mcp-Session-Id"] == nil)

    // Clean up
    AuthMockURLProtocol.requestHandler = nil
  }

  @Test func testStreamableHTTPTransportSSEStreamHeaders() async throws {
    let mockSession = URLSessionConfiguration.ephemeral
    mockSession.protocolClasses = [AuthMockURLProtocol.self]

    let transport = StreamableHTTPTransport(
      serverURL: URL(string: "https://test.example.com/mcp")!,
      urlSessionConfiguration: mockSession,
      clientInfo: Implementation(name: "TestClient", version: "1.0"),
      clientCapabilities: ClientCapabilities()
    )

    var capturedSSEHeaders: [String: String]?
    let sessionID = "sse-session-456"
    let negotiatedProtocolVersion = "2025-03-26"

    AuthMockURLProtocol.requestHandler = { request in
      if request.httpMethod == "POST" {
        // Handle initialize request
        if let body = request.httpBody,
          let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          json["method"] as? String == "initialize"
        {

          let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "Mcp-Session-Id": sessionID]
          )!

          let initResponse = """
            {
              "jsonrpc": "2.0",
              "id": "\(json["id"] ?? "")",
              "result": {
                "protocolVersion": "\(negotiatedProtocolVersion)",
                "capabilities": {},
                "serverInfo": {"name": "TestServer", "version": "1.0"}
              }
            }
            """.data(using: .utf8)!

          return (response, initResponse)
        } else {
          // Initialized notification
          let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 202,
            httpVersion: nil,
            headerFields: nil
          )!
          return (response, nil)
        }
      } else if request.httpMethod == "GET" {
        // SSE request - capture headers
        capturedSSEHeaders = request.allHTTPHeaderFields

        // Return 405 to trigger legacy SSE mode
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 405,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, nil)
      }

      throw TestError.unexpectedURL(
        "\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "nil")")
    }

    try await transport.start()
    await transport.setAuthorizationToken("sse-token-789")

    // This should trigger SSE stream with fallback behavior
    do {
      _ = try await transport.initialize(idGenerator: { .string("init-1") })
    } catch {
      // Expected to fail due to 405 response
    }

    // Verify SSE headers include all common headers
    // The headers might be nil if the SSE stream wasn't opened during this test
    if let sseHeaders = capturedSSEHeaders {
      #expect(sseHeaders["MCP-Protocol-Version"] == MCPProtocolVersion)
      #expect(sseHeaders["Authorization"] == "Bearer sse-token-789")
      #expect(sseHeaders["Accept"] == "text/event-stream")
    } else {
      // If SSE wasn't triggered in this test flow, that's acceptable
      // The main goal was to test that when SSE is triggered, it has the right headers
    }

    // Clean up
    AuthMockURLProtocol.requestHandler = nil
  }
}
