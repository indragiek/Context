// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite(.serialized, .timeLimit(.minutes(1))) struct StdioTransportTests {
  @Test func testReceiveLogs() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()
    let logs = try await transport.receiveLogs()

    let firstLog = try await withTimeout(
      timeoutMessage: "Receive logs timed out after 5 seconds",
      defaultValue: nil as String?
    ) {
      try await logs.first { _ in true }
    }

    #expect(firstLog == "running mcp server")
    try await transport.close()
  }

  @Test func testSendAndReceive() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()
    let initialize = InitializeRequest(
      id: 1,
      protocolVersion: MCPProtocolVersion,
      capabilities: TestFixtures.clientCapabilities,
      clientInfo: TestFixtures.clientInfo)
    let result = try await transport.testOnly_sendAndWaitForResponse(request: initialize)
    switch result {
    case let .successfulRequest(request: request, response: response):
      #expect(
        (try TestFixtures.jsonEncoder.encode(request))
          == (try TestFixtures.jsonEncoder.encode(initialize)))
      let expectedResponse = InitializeResponse(
        id: 1,
        protocolVersion: StdioTransportTestFixtures.echoServerProtocolVersion,
        capabilities: StdioTransportTestFixtures.echoServerCapabilities,
        serverInfo: StdioTransportTestFixtures.echoServerInfo
      )
      #expect(
        (try TestFixtures.jsonEncoder.encode(response))
          == (try TestFixtures.jsonEncoder.encode(expectedResponse)))
    default:
      recordErrorsForNonSuccessfulResponse(result)
    }
    try await transport.close()
  }

  @Test func testInitialization() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()
    let initializeResult = try await transport.initialize(idGenerator: {
      JSONRPCRequestID.string(UUID().uuidString)
    })
    #expect(
      initializeResult.protocolVersion == StdioTransportTestFixtures.echoServerProtocolVersion)
    #expect(initializeResult.capabilities == StdioTransportTestFixtures.echoServerCapabilities)
    #expect(initializeResult.serverInfo == StdioTransportTestFixtures.echoServerInfo)
    try await transport.close()
  }

  @Test func testSendNotification() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()
    let initialized = InitializedNotification()
    try await transport.send(notification: initialized)
    try await Task.sleep(for: .milliseconds(50))
    try await transport.close()
  }

  @Test func testCloseAndRestart() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()
    try await transport.close()

    try await transport.start()
    let logs = try await transport.receiveLogs()

    let firstLog = try await withTimeout(
      timeoutMessage: "Restart logs timed out after 5 seconds",
      defaultValue: nil as String?
    ) {
      try await logs.first { _ in true }
    }
    #expect(firstLog == "running mcp server")
    try await transport.close()
  }

  @Test func testReceiveAfterSendingMultipleRequests() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()

    let request1 = InitializeRequest(
      id: 1,
      protocolVersion: MCPProtocolVersion,
      capabilities: TestFixtures.clientCapabilities,
      clientInfo: TestFixtures.clientInfo)

    let request2 = InitializeRequest(
      id: 2,
      protocolVersion: MCPProtocolVersion,
      capabilities: TestFixtures.clientCapabilities,
      clientInfo: TestFixtures.clientInfo)

    try await transport.send(request: request1)
    try await transport.send(request: request2)

    var receivedResponses = 0
    for try await _ in try await transport.receive() {
      receivedResponses += 1
      if receivedResponses == 2 {
        break
      }
    }

    #expect(receivedResponses == 2)
    try await transport.close()
  }

  @Test func testResponseMatching() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()

    let request1 = InitializeRequest(
      id: "req1",
      protocolVersion: MCPProtocolVersion,
      capabilities: TestFixtures.clientCapabilities,
      clientInfo: TestFixtures.clientInfo)

    let request2 = InitializeRequest(
      id: "req2",
      protocolVersion: MCPProtocolVersion,
      capabilities: TestFixtures.clientCapabilities,
      clientInfo: TestFixtures.clientInfo)

    async let response1Task = transport.testOnly_sendAndWaitForResponse(request: request1)
    async let response2Task = transport.testOnly_sendAndWaitForResponse(request: request2)

    let (response1, response2) = try await (response1Task, response2Task)

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
  }

  @Test func testCloseBeforeStart() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.close()
  }

  @Test func testStartMultipleTimes() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()
    try await transport.start()
    let logs = try await transport.receiveLogs()

    let firstLog = try await withTimeout(
      timeoutMessage: "Start multiple times logs timed out after 5 seconds",
      defaultValue: nil as String?
    ) {
      try await logs.first { _ in true }
    }
    #expect(firstLog == "running mcp server")
    try await transport.close()
  }

  @Test(.timeLimit(.minutes(1))) func testReceiveConnectionState() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")

    let stateChannel = try await transport.receiveConnectionState()
    try await transport.start()
    let task = Task {
      try await withTimeout(
        timeoutMessage: "Connection state test timed out after 5 seconds",
        defaultValue: [] as [TransportConnectionState]
      ) {
        var states = [TransportConnectionState]()
        for try await state in stateChannel {
          states.append(state)
          if states.count >= 3 {
            break
          }
        }
        return states
      }
    }

    try await transport.close()
    try await transport.start()
    try await transport.close()

    let states = try await task.value
    #expect(states.count == 3)
    #expect(states[0] == .connected)
    #expect(states[1] == .disconnected)
    #expect(states[2] == .connected)
  }

  @Test func testDifferentIDTypes() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()

    let stringIDRequest = InitializeRequest(
      id: "string-id",
      protocolVersion: MCPProtocolVersion,
      capabilities: TestFixtures.clientCapabilities,
      clientInfo: TestFixtures.clientInfo)

    let numberIDRequest = InitializeRequest(
      id: 42,
      protocolVersion: MCPProtocolVersion,
      capabilities: TestFixtures.clientCapabilities,
      clientInfo: TestFixtures.clientInfo)

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
  }

  @Test func testReceiveNoResponses() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()

    let task = Task {
      var count = 0
      for try await _ in try await transport.receive() {
        count += 1
        if count > 0 {
          break
        }
      }
      return count
    }

    // No requests sent, so we shouldn't receive any responses
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()

    do {
      let count = try await task.value
      #expect(count == 0)
    } catch is CancellationError {
      // This is also acceptable
    }

    try await transport.close()
  }

  @Test func testConcurrentOperations() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()

    // Create multiple concurrent tasks that send requests and notifications
    try await withThrowingTaskGroup(of: Void.self) { group in
      // Send requests
      for i in 1...3 {
        group.addTask {
          let request = InitializeRequest(
            id: .number(i),
            protocolVersion: MCPProtocolVersion,
            capabilities: TestFixtures.clientCapabilities,
            clientInfo: TestFixtures.clientInfo)
          try await transport.send(request: request)
        }
      }

      // Send notifications
      for _ in 1...3 {
        group.addTask {
          let notification = InitializedNotification()
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

      // Also receive logs simultaneously
      group.addTask {
        try await withTimeout(
          timeoutMessage: "Receive logs timed out after 5 seconds",
          defaultValue: ()
        ) {
          var count = 0
          for try await _ in try await transport.receiveLogs() {
            count += 1
            if count >= 1 {
              break
            }
          }
        }
      }

      try await group.waitForAll()
    }

    try await transport.close()
  }

  @Test func testSequentialRequestsAndResponses() async throws {
    let transport = TestFixtures.createStdioTransport(serverName: "echo")
    try await transport.start()

    // Send 10 requests and verify we get 10 responses in order
    let numberOfRequests = 10
    for i in 1...numberOfRequests {
      let request = InitializeRequest(
        id: .number(i),
        protocolVersion: MCPProtocolVersion,
        capabilities: TestFixtures.clientCapabilities,
        clientInfo: TestFixtures.clientInfo)
      try await transport.send(request: request)
    }

    var receivedIDs = [JSONRPCRequestID]()

    receivedIDs = try await withTimeout(
      timeoutMessage: "Timeout waiting for sequential request responses",
      defaultValue: [JSONRPCRequestID]()
    ) {
      var collectedIDs = [JSONRPCRequestID]()
      var responseCount = 0

      for try await response in try await transport.receive() {
        if case let .successfulRequest(request: request, _) = response {
          collectedIDs.append(request.id)
        }

        responseCount += 1
        if responseCount >= numberOfRequests {
          break
        }
      }
      return collectedIDs
    }

    // Check that we received all responses
    #expect(receivedIDs.count == numberOfRequests)

    // Check that IDs are in the expected range
    let expectedIDs = (1...numberOfRequests).map { JSONRPCRequestID.number($0) }
    for id in expectedIDs {
      #expect(receivedIDs.contains { $0 == id })
    }

    try await transport.close()
  }

  // MARK: - Race Condition Tests

  @Test func testInitializeAfterFailedStart() async throws {
    // Create a transport with an invalid executable path
    let serverProcessInfo = StdioTransport.ServerProcessInfo(
      executableURL: URL(fileURLWithPath: "/non/existent/path/to/executable"),
      arguments: []
    )

    let transport = StdioTransport(
      serverProcessInfo: serverProcessInfo,
      clientInfo: Implementation(name: "TestClient", version: "1.0"),
      clientCapabilities: ClientCapabilities()
    )

    // Try to start the transport - this should fail because the executable doesn't exist
    do {
      try await transport.start()
      Issue.record("Expected start() to fail with non-existent executable")
    } catch {
      // Expected error - the executable doesn't exist
    }

    // Now try to initialize - this should throw TransportError.notStarted instead of crashing
    do {
      _ = try await transport.initialize { .string("test-id") }
      Issue.record("Expected initialize() to throw TransportError.notStarted")
    } catch TransportError.notStarted {
      // This is the expected error - test passes
    } catch {
      Issue.record("Expected TransportError.notStarted but got \(error)")
    }
  }

  @Test func testReceiveAfterFailedStart() async throws {
    let serverProcessInfo = StdioTransport.ServerProcessInfo(
      executableURL: URL(fileURLWithPath: "/non/existent/path/to/executable"),
      arguments: []
    )

    let transport = StdioTransport(
      serverProcessInfo: serverProcessInfo,
      clientInfo: Implementation(name: "TestClient", version: "1.0"),
      clientCapabilities: ClientCapabilities()
    )

    // Try to start the transport - this should fail
    do {
      try await transport.start()
      Issue.record("Expected start() to fail with non-existent executable")
    } catch {
      // Expected error
    }

    // Now try to receive - this should throw TransportError.notStarted instead of crashing
    do {
      _ = try await transport.receive()
      Issue.record("Expected receive() to throw TransportError.notStarted")
    } catch TransportError.notStarted {
      // This is the expected error - test passes
    } catch {
      Issue.record("Expected TransportError.notStarted but got \(error)")
    }
  }

  @Test func testReceiveLogsAfterFailedStart() async throws {
    let serverProcessInfo = StdioTransport.ServerProcessInfo(
      executableURL: URL(fileURLWithPath: "/non/existent/path/to/executable"),
      arguments: []
    )

    let transport = StdioTransport(
      serverProcessInfo: serverProcessInfo,
      clientInfo: Implementation(name: "TestClient", version: "1.0"),
      clientCapabilities: ClientCapabilities()
    )

    // Try to start the transport - this should fail
    do {
      try await transport.start()
      Issue.record("Expected start() to fail with non-existent executable")
    } catch {
      // Expected error
    }

    // Now try to receiveLogs - this should throw TransportError.notStarted instead of crashing
    do {
      _ = try await transport.receiveLogs()
      Issue.record("Expected receiveLogs() to throw TransportError.notStarted")
    } catch TransportError.notStarted {
      // This is the expected error - test passes
    } catch {
      Issue.record("Expected TransportError.notStarted but got \(error)")
    }
  }

  @Test func testSendAfterFailedStart() async throws {
    let serverProcessInfo = StdioTransport.ServerProcessInfo(
      executableURL: URL(fileURLWithPath: "/non/existent/path/to/executable"),
      arguments: []
    )

    let transport = StdioTransport(
      serverProcessInfo: serverProcessInfo,
      clientInfo: Implementation(name: "TestClient", version: "1.0"),
      clientCapabilities: ClientCapabilities()
    )

    // Try to start the transport - this should fail
    do {
      try await transport.start()
      Issue.record("Expected start() to fail with non-existent executable")
    } catch {
      // Expected error
    }

    // Create a test request using InitializeRequest
    let request = InitializeRequest(
      id: .number(1),
      protocolVersion: MCPProtocolVersion,
      capabilities: ClientCapabilities(),
      clientInfo: Implementation(name: "TestClient", version: "1.0")
    )

    // Now try to send - this should throw TransportError.notStarted instead of crashing
    do {
      try await transport.send(request: request)
      Issue.record("Expected send() to throw TransportError.notStarted")
    } catch TransportError.notStarted {
      // This is the expected error - test passes
    } catch {
      Issue.record("Expected TransportError.notStarted but got \(error)")
    }
  }
}

private struct StdioTransportTestFixtures {
  static let echoServerCapabilities: ServerCapabilities = {
    var serverCapabilities = ServerCapabilities()
    serverCapabilities.tools = .init(listChanged: false)
    serverCapabilities.resources = .init(subscribe: false, listChanged: false)
    serverCapabilities.prompts = .init(listChanged: false)
    return serverCapabilities
  }()

  static let echoServerInfo = Implementation(name: "Echo", version: "1.8.0")
  static let echoServerProtocolVersion = "2024-11-05"
}
