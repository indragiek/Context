// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing
import os

@testable import ContextCore

@Suite(.serialized, .timeLimit(.minutes(1))) struct StreamableHTTPTransportTests {
  @Test func testInitialization() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    let initializeResult = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    #expect(
      initializeResult.protocolVersion
        == StreamableHTTPTransportTestFixtures.echoServerProtocolVersion)
    #expect(
      initializeResult.capabilities == StreamableHTTPTransportTestFixtures.echoServerCapabilities)
    #expect(initializeResult.serverInfo == StreamableHTTPTransportTestFixtures.echoServerInfo)

    try await transport.close()
    server.terminate()
  }

  @Test func testSendAndReceiveRequest() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    let request = ListToolsRequest(id: "test-request-id", cursor: nil)

    let response = try await transport.testOnly_sendAndWaitForResponse(request: request)
    switch response {
    case let .successfulRequest(request: receivedRequest, response: receivedResponse):
      #expect(receivedRequest.id == request.id)
      guard let toolsResponse = receivedResponse as? ListToolsResponse else {
        Issue.record("Expected ListToolsResponse, but got \(type(of: receivedResponse))")
        return
      }
      // The echo server should return something, but we don't need to validate exact contents
      #expect(toolsResponse.id == request.id)
    default:
      recordErrorsForNonSuccessfulResponse(response)
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testSendNotification() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    let notification = RootsListChangedNotification()
    // Since notifications don't expect responses, we just verify it doesn't throw
    try await transport.send(notification: notification)

    try await transport.close()
    server.terminate()
  }

  @Test func testMultipleRequests() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    let request1 = ListToolsRequest(id: "request-1", cursor: nil)
    let request2 = ListToolsRequest(id: "request-2", cursor: nil)

    async let response1Future = transport.testOnly_sendAndWaitForResponse(request: request1)
    async let response2Future = transport.testOnly_sendAndWaitForResponse(request: request2)

    let (response1, response2) = try await (response1Future, response2Future)

    if case let .successfulRequest(request: request, _) = response1 {
      #expect(request.id == request1.id)
    } else {
      recordErrorsForNonSuccessfulResponse(response1)
    }

    if case let .successfulRequest(request: request, _) = response2 {
      #expect(request.id == request2.id)
    } else {
      recordErrorsForNonSuccessfulResponse(response2)
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testConcurrentOperations() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Create multiple concurrent tasks that send requests and notifications
    try await withThrowingTaskGroup(of: Void.self) { group in
      // Send requests
      for i in 1...3 {
        group.addTask {
          let request = ListToolsRequest(id: .number(i), cursor: nil)
          try await transport.send(request: request)
        }
      }

      // Send notifications
      for _ in 1...3 {
        group.addTask {
          let notification = RootsListChangedNotification()
          try await transport.send(notification: notification)
        }
      }

      // Receive responses
      group.addTask {
        try await withTimeout(
          timeoutMessage: "Receive responses timed out after 5 seconds",
          defaultValue: ()
        ) {
          var count = 0
          for try await _ in try await transport.receive() {
            count += 1
            if count >= 3 {
              break
            }
          }
        }
      }

      try await group.waitForAll()
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testCloseAndRestart() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    try await transport.close()

    // Restart transport
    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Verify transport works after restart
    let request = ListToolsRequest(id: "after-restart", cursor: nil)
    let response = try await transport.testOnly_sendAndWaitForResponse(request: request)

    if case let .successfulRequest(request: receivedRequest, _) = response {
      #expect(receivedRequest.id == request.id)
    } else {
      recordErrorsForNonSuccessfulResponse(response)
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testSequentialRequests() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Send 5 sequential requests and verify responses
    let numberOfRequests = 5
    var receivedResponses = 0

    for i in 1...numberOfRequests {
      let request = ListToolsRequest(id: .number(i), cursor: nil)

      let response = try await transport.testOnly_sendAndWaitForResponse(request: request)

      if case .successfulRequest = response {
        receivedResponses += 1
      }
    }

    #expect(receivedResponses == numberOfRequests)

    try await transport.close()
    server.terminate()
  }

  @Test func testDifferentIDTypes() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    let stringIDRequest = ListToolsRequest(id: "string-id-123", cursor: nil)
    let numberIDRequest = ListToolsRequest(id: 456, cursor: nil)

    let stringResponse = try await transport.testOnly_sendAndWaitForResponse(
      request: stringIDRequest)
    if case let .successfulRequest(request: request, _) = stringResponse {
      #expect(request.id == stringIDRequest.id)
    } else {
      recordErrorsForNonSuccessfulResponse(stringResponse)
    }

    let numberResponse = try await transport.testOnly_sendAndWaitForResponse(
      request: numberIDRequest)
    if case let .successfulRequest(request: request, _) = numberResponse {
      #expect(request.id == numberIDRequest.id)
    } else {
      recordErrorsForNonSuccessfulResponse(numberResponse)
    }

    try await transport.close()
    server.terminate()
  }

  @Test(.disabled("FastMCP (the test server) does not yet support batching"))
  func testSendBatchRequests() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Create batch with multiple requests
    let request1 = ListToolsRequest(id: "batch-request-1", cursor: nil)
    let request2 = ListToolsRequest(id: "batch-request-2", cursor: nil)
    let request3 = ListToolsRequest(id: "batch-request-3", cursor: nil)

    let batchItems: [JSONRPCBatchItem] = [
      .request(request1),
      .request(request2),
      .request(request3),
    ]

    // Send batch
    try await transport.send(batch: batchItems)

    // Receive and verify responses for all requests in the batch
    let (receivedResponses, remainingRequestIDs) = try await withTimeout(
      timeoutMessage: "Timeout waiting for batch request responses",
      defaultValue: (0, Set([request1.id, request2.id, request3.id]))
    ) {
      var responseCount = 0
      var requestIDs = Set([request1.id, request2.id, request3.id])

      for try await response in try await transport.receive() {
        switch response {
        case let .successfulRequest(request: request, _):
          if requestIDs.contains(request.id) {
            requestIDs.remove(request.id)
            responseCount += 1
          }
        default:
          recordErrorsForNonSuccessfulResponse(response)
        }

        // Break once we've received all responses
        if responseCount == 3 {
          break
        }
      }
      return (responseCount, requestIDs)
    }

    #expect(receivedResponses == 3)
    #expect(remainingRequestIDs.isEmpty)

    try await transport.close()
    server.terminate()
  }

  @Test(.disabled("FastMCP (the test server) does not yet support batching"))
  func testReceiveBatchResponses() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Create multiple requests to receive responses in a batch
    let request1 = ListToolsRequest(id: "batch-response-1", cursor: nil)
    let request2 = ListToolsRequest(id: "batch-response-2", cursor: nil)
    let request3 = ListToolsRequest(id: "batch-response-3", cursor: nil)

    // Send individual requests but quickly in succession to encourage
    // the server to batch responses
    async let response1Future = transport.testOnly_sendAndWaitForResponse(request: request1)
    async let response2Future = transport.testOnly_sendAndWaitForResponse(request: request2)
    async let response3Future = transport.testOnly_sendAndWaitForResponse(request: request3)

    // Await all responses - we're expecting each testOnly_sendAndWaitForResponse call
    // to succeed, meaning all responses were properly received and processed
    let responses = try await [response1Future, response2Future, response3Future]

    // Verify each response matches its corresponding request
    let responseIDs = responses.compactMap { response -> JSONRPCRequestID? in
      switch response {
      case let .successfulRequest(request: request, _):
        return request.id
      case .failedRequest, .serverNotification, .serverRequest, .serverError, .decodingError:
        return nil
      }
    }

    #expect(responseIDs.count == 3)
    #expect(Set(responseIDs) == Set([request1.id, request2.id, request3.id]))

    // Verify each individual response
    for response in responses {
      switch response {
      case let .successfulRequest(request: request, response: receivedResponse):
        guard let toolsResponse = receivedResponse as? ListToolsResponse else {
          Issue.record(
            "Expected ListToolsResponse, but got \(type(of: receivedResponse))")
          continue
        }
        #expect(toolsResponse.id == request.id)
      default:
        recordErrorsForNonSuccessfulResponse(response)
      }
    }

    try await transport.close()
    server.terminate()
  }

  @Test(.disabled("FastMCP (the test server) does not yet support batching"))
  func testMixedBatch() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Create a batch with a mix of requests and notifications
    let request1 = ListToolsRequest(id: "mixed-batch-request-1", cursor: nil)
    let request2 = ListToolsRequest(id: "mixed-batch-request-2", cursor: nil)
    let notification1 = RootsListChangedNotification()
    let notification2 = RootsListChangedNotification()

    let batchItems: [JSONRPCBatchItem] = [
      .request(request1),
      .notification(notification1),
      .request(request2),
      .notification(notification2),
    ]

    // Send the mixed batch
    try await transport.send(batch: batchItems)

    // Only requests should receive responses, not notifications
    let expectedRequests = Set([request1.id, request2.id])

    let receivedRequests = try await withTimeout(
      timeoutMessage: "Timeout waiting for mixed batch responses",
      defaultValue: Set<JSONRPCRequestID>()
    ) {
      var collectedRequests = Set<JSONRPCRequestID>()

      for try await response in try await transport.receive() {
        switch response {
        case let .successfulRequest(request: request, _):
          if expectedRequests.contains(request.id) {
            collectedRequests.insert(request.id)
          }
        default:
          recordErrorsForNonSuccessfulResponse(response)
        }

        // Break once we've received all expected request responses
        if collectedRequests == expectedRequests {
          break
        }
      }
      return collectedRequests
    }

    // Verify we received responses only for the requests, not for notifications
    #expect(receivedRequests.count == 2)
    #expect(receivedRequests == expectedRequests)

    try await transport.close()
    server.terminate()
  }

  @Test func testStartMultipleTimes() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    // Start multiple times should not cause issues
    try await transport.start()
    try await transport.start()

    let initializeResult = try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    #expect(
      initializeResult.protocolVersion
        == StreamableHTTPTransportTestFixtures.echoServerProtocolVersion)

    try await transport.close()
    server.terminate()
  }

  @Test func testCloseBeforeStart() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    // Close before start should not cause issues
    try await transport.close()

    // Should still be able to start and use transport
    try await transport.start()
    let initializeResult = try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    #expect(
      initializeResult.protocolVersion
        == StreamableHTTPTransportTestFixtures.echoServerProtocolVersion)

    try await transport.close()
    server.terminate()
  }

  @Test func testReceiveLogMessages() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-logging", port: 9000)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    try await confirmation(expectedCount: 1) { receivedLog in
      Task {
        let _ = try await withTimeout(
          timeoutMessage: "Timeout waiting for log messages",
          defaultValue: false
        ) {
          for try await response in try await transport.receive() {
            switch response {
            case .successfulRequest:
              break
            case .serverNotification(let notification):
              if let log = notification as? LoggingMessageNotification {
                #expect(log.params.level == LoggingLevel.info)
                if case let .string(message) = log.params.data {
                  #expect(message.contains("Running the echo tool"))
                  receivedLog()
                  return true
                } else {
                  Issue.record("Log message didn't contain expected text data")
                }
              } else {
                recordErrorsForNonSuccessfulResponse(response)
              }
            default:
              recordErrorsForNonSuccessfulResponse(response)
            }
          }
          return false
        }
      }
      let toolCall = CallToolRequest(
        id: "log-test-id",
        name: "echo_tool",
        arguments: ["message": "Hello logging!"]
      )
      _ = try await transport.testOnly_sendAndWaitForResponse(request: toolCall)
      // The log messages are not received synchronously alongside the tool call response
      // so wait for the logs to be received.
      try await Task.sleep(for: .milliseconds(10))
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testSSEConnectionStateTracking() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()

    let connectionStateTask = Task {
      try await withTimeout(
        timeoutMessage: "Connection state tracking timed out after 5 seconds",
        defaultValue: [] as [TransportConnectionState]
      ) {
        var states: [TransportConnectionState] = []
        for try await state in try await transport.receiveConnectionState() {
          states.append(state)
          if state == .disconnected && states.count >= 2 {
            break
          }
        }
        return states
      }
    }

    // Trigger connection
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Send a request to ensure connection is working
    let request = ListToolsRequest(id: "state-test-id", cursor: nil)
    _ = try await transport.testOnly_sendAndWaitForResponse(request: request)

    // Trigger disconnection
    try await transport.close()
    let connectionStates = try await connectionStateTask.value

    #expect(connectionStates.contains(.connected))
    #expect(connectionStates.contains(.disconnected))

    server.terminate()
  }

  @Test func testSSEConnectionCountAccuracy() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    try await transport.start()

    let connectionStateTask = Task {
      try await withTimeout(
        timeoutMessage: "Connection count accuracy test timed out after 5 seconds",
        defaultValue: (0, 0)
      ) {
        var connectedCount = 0
        var disconnectedCount = 0
        for try await state in try await transport.receiveConnectionState() {
          switch state {
          case .connected:
            connectedCount += 1
          case .disconnected:
            disconnectedCount += 1
          }
          if state == .disconnected && connectedCount > 0 {
            break
          }
        }
        return (connectedCount, disconnectedCount)
      }
    }

    // Trigger connection
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Send multiple requests - should not affect connection count
    for i in 1...3 {
      let request = ListToolsRequest(id: .number(i), cursor: nil)
      _ = try await transport.testOnly_sendAndWaitForResponse(request: request)
    }

    // Trigger disconnection
    try await transport.close()
    let (connectedCount, disconnectedCount) = try await connectionStateTask.value

    // Should see exactly one connection and one disconnection
    #expect(connectedCount == 1, "Expected exactly 1 connection, got \(connectedCount)")
    #expect(disconnectedCount == 1, "Expected exactly 1 disconnection, got \(disconnectedCount)")

    server.terminate()
  }

  @Test func testSSEConnectionCountWithRestart() async throws {
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9000)
    let transport = server.createTransport()

    let connectionStateTask = Task {
      try await withTimeout(
        timeoutMessage: "Connection count with restart test timed out after 5 seconds",
        defaultValue: (0, 0)
      ) {
        var connectedCount = 0
        var disconnectedCount = 0
        for try await state in try await transport.receiveConnectionState() {
          switch state {
          case .connected:
            connectedCount += 1
          case .disconnected:
            disconnectedCount += 1
          }
          if state == .disconnected && disconnectedCount >= 2 {
            break
          }
        }
        return (connectedCount, disconnectedCount)
      }
    }

    // First session
    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    try await transport.close()

    // Second session
    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    try await transport.close()

    let (connectedCount, disconnectedCount) = try await connectionStateTask.value

    // Should see exactly two connections and two disconnections
    #expect(connectedCount == 2, "Expected exactly 2 connections, got \(connectedCount)")
    #expect(disconnectedCount == 2, "Expected exactly 2 disconnections, got \(disconnectedCount)")

    server.terminate()
  }

  @Test func testKeepAliveHeaderParsing() async throws {
    // Start server with Keep-Alive timeout of 5 seconds (default)
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-keepalive", port: 9000)
    
    // Create transport with custom logger
    let logger = Logger(subsystem: "com.test", category: "StreamableHTTPTransport")
    let transport = StreamableHTTPTransport(
      serverURL: server.serverURL,
      urlSessionConfiguration: {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3600
        return config
      }(),
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities,
      encoder: TestFixtures.jsonEncoder,
      logger: logger
    )

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Wait for SSE connection to be established and Keep-Alive headers to be processed
    try await Task.sleep(for: .seconds(2))

    // The transport should have detected the Keep-Alive header and set up ping interval
    // The ping interval should be 80% of the timeout value (4 seconds for 5 second timeout)
    let interval = await transport.pingInterval
    #expect(interval != nil, "Ping interval should be set after receiving Keep-Alive header")
    if let pingInterval = interval {
      #expect(pingInterval == 4.0, "Ping interval should be 80% of Keep-Alive timeout (4s for 5s timeout)")
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testAutomaticPingOnKeepAlive() async throws {
    // Start server with Keep-Alive timeout of 3 seconds
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-keepalive", port: 9001)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Reset ping count on the server
    let resetRequest = CallToolRequest(
      id: "reset-ping-count",
      name: "reset_ping_count",
      arguments: [:]
    )
    _ = try await transport.testOnly_sendAndWaitForResponse(request: resetRequest)

    // Wait for automatic pings to be sent (should be sent every 2.4 seconds)
    try await Task.sleep(for: .seconds(5.5))

    // Check how many pings were sent
    let getPingCountRequest = CallToolRequest(
      id: "get-ping-count",
      name: "get_ping_count",
      arguments: [:]
    )
    let response = try await transport.testOnly_sendAndWaitForResponse(request: getPingCountRequest)

    switch response {
    case let .successfulRequest(request: _, response: receivedResponse):
      guard let toolResponse = receivedResponse as? CallToolResponse else {
        Issue.record("Expected CallToolResponse, but got \(type(of: receivedResponse))")
        return
      }
      // Should have sent at least 2 pings in 5.5 seconds (at 2.4s intervals)
      if let firstContent = toolResponse.result.content.first,
         case let .text(text, annotations: _) = firstContent,
         let pingCount = Int(text) {
        #expect(pingCount >= 2, "Should have sent at least 2 pings in 5.5 seconds, but got \(pingCount)")
        #expect(pingCount <= 3, "Should have sent at most 3 pings in 5.5 seconds, but got \(pingCount)")
      } else {
        Issue.record("Expected integer ping count in response content")
      }
    default:
      recordErrorsForNonSuccessfulResponse(response)
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testPingTimerResetOnRequest() async throws {
    // Start server with Keep-Alive timeout of 3 seconds
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-keepalive", port: 9002)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Reset ping count on the server
    let resetRequest = CallToolRequest(
      id: "reset-ping-count",
      name: "reset_ping_count",
      arguments: [:]
    )
    _ = try await transport.testOnly_sendAndWaitForResponse(request: resetRequest)

    // Send requests continuously for 5 seconds (should prevent pings)
    let startTime = Date()
    var requestCount = 0
    while Date().timeIntervalSince(startTime) < 5.0 {
      let echoRequest = CallToolRequest(
        id: .string("echo-\(requestCount)"),
        name: "echo_tool",
        arguments: ["message": "Keeping connection active"]
      )
      _ = try await transport.testOnly_sendAndWaitForResponse(request: echoRequest)
      requestCount += 1
      try await Task.sleep(for: .milliseconds(500))
    }

    // Check ping count - should be 0 or very low since we kept sending requests
    let getPingCountRequest = CallToolRequest(
      id: "get-ping-count",
      name: "get_ping_count",
      arguments: [:]
    )
    let response = try await transport.testOnly_sendAndWaitForResponse(request: getPingCountRequest)

    switch response {
    case let .successfulRequest(request: _, response: receivedResponse):
      guard let toolResponse = receivedResponse as? CallToolResponse else {
        Issue.record("Expected CallToolResponse, but got \(type(of: receivedResponse))")
        return
      }
      if let firstContent = toolResponse.result.content.first,
         case let .text(text, annotations: _) = firstContent,
         let pingCount = Int(text) {
        #expect(pingCount <= 1, "Should have sent at most 1 ping during active communication, but got \(pingCount)")
      } else {
        Issue.record("Expected integer ping count in response content")
      }
    default:
      recordErrorsForNonSuccessfulResponse(response)
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testPingContinuesAfterIdle() async throws {
    // Start server with Keep-Alive timeout of 2 seconds
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-keepalive", port: 9003)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Reset ping count on the server
    let resetRequest = CallToolRequest(
      id: "reset-ping-count",
      name: "reset_ping_count",
      arguments: [:]
    )
    _ = try await transport.testOnly_sendAndWaitForResponse(request: resetRequest)

    // Send a request to reset the ping timer
    let echoRequest = CallToolRequest(
      id: "echo-test",
      name: "echo_tool",
      arguments: ["message": "Test message"]
    )
    _ = try await transport.testOnly_sendAndWaitForResponse(request: echoRequest)

    // Reset ping count again after the request
    _ = try await transport.testOnly_sendAndWaitForResponse(request: resetRequest)

    // Wait for pings to resume after idle period
    try await Task.sleep(for: .seconds(3.5))

    // Check ping count
    let getPingCountRequest = CallToolRequest(
      id: "get-ping-count",
      name: "get_ping_count",
      arguments: [:]
    )
    let response = try await transport.testOnly_sendAndWaitForResponse(request: getPingCountRequest)

    switch response {
    case let .successfulRequest(request: _, response: receivedResponse):
      guard let toolResponse = receivedResponse as? CallToolResponse else {
        Issue.record("Expected CallToolResponse, but got \(type(of: receivedResponse))")
        return
      }
      if let firstContent = toolResponse.result.content.first,
         case let .text(text, annotations: _) = firstContent,
         let pingCount = Int(text) {
        #expect(pingCount >= 2, "Should have sent at least 2 pings after idle period, but got \(pingCount)")
      } else {
        Issue.record("Expected integer ping count in response content")
      }
    default:
      recordErrorsForNonSuccessfulResponse(response)
    }

    try await transport.close()
    server.terminate()
  }

  @Test func testNoKeepAliveNoPing() async throws {
    // Use regular echo server without Keep-Alive headers
    let server = try HTTPTestServer(
      streamableHTTP: true, scriptName: "echo-http-streamable", port: 9004)
    let transport = server.createTransport()

    try await transport.start()
    _ = try await transport.initialize(idGenerator: TestFixtures.idGenerator)

    // Ping interval should not be set for servers without Keep-Alive headers
    let interval = await transport.pingInterval
    #expect(interval == nil, "Ping interval should not be set without Keep-Alive header")

    // Wait a bit to ensure no pings would be sent
    try await Task.sleep(for: .seconds(2))

    // Transport should still work normally
    let request = ListToolsRequest(id: "no-keepalive-test", cursor: nil)
    let response = try await transport.testOnly_sendAndWaitForResponse(request: request)

    if case .successfulRequest = response {
      // Success - transport works without Keep-Alive
    } else {
      recordErrorsForNonSuccessfulResponse(response)
    }

    try await transport.close()
    server.terminate()
  }

}

@JSONRPCNotification(method: "notifications/roots/list_changed")
private struct RootsListChangedNotification {
  struct Params: Codable, Sendable {}
}

private struct StreamableHTTPTransportTestFixtures {
  static let echoServerCapabilities: ServerCapabilities = {
    var serverCapabilities = ServerCapabilities()
    serverCapabilities.tools = .init(listChanged: false)
    serverCapabilities.resources = .init(subscribe: false, listChanged: false)
    serverCapabilities.resources = .init(subscribe: false, listChanged: false)
    serverCapabilities.prompts = .init(listChanged: false)
    return serverCapabilities
  }()

  static let echoServerInfo = Implementation(name: "Echo", version: "1.8.1")
  static let echoServerProtocolVersion = "2024-11-05"
}
