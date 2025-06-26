// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

/// Shared test fixtures and utilities
public struct TestFixtures {
  public static let clientInfo = Implementation(name: "SwiftMCPTest", version: "1.0.0")

  public static let clientCapabilities: ClientCapabilities = {
    var clientCapabilities = ClientCapabilities()
    clientCapabilities.roots = ClientCapabilities.Roots(listChanged: true)
    clientCapabilities.sampling = ClientCapabilities.Sampling()
    return clientCapabilities
  }()

  public static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return encoder
  }()

  public static let idGenerator: Transport.IDGenerator = {
    JSONRPCRequestID.string(UUID().uuidString)
  }

  /// Creates a StdioTransport connected to a bundled Python MCP server
  public static func createStdioTransport(serverName: String) -> StdioTransport {
    let bundle = Bundle.module
    let serverURL = bundle.url(
      forResource: serverName, withExtension: "py", subdirectory: "mcp-servers")!
    let uvPath =
      ProcessInfo.processInfo.environment["UV_PATH"] ?? "/opt/homebrew/bin/uv"
    let serverProcessInfo = StdioTransport.ServerProcessInfo(
      executableURL: URL(filePath: uvPath),
      arguments: ["run", "-qq", serverURL.lastPathComponent],
      currentDirectoryURL: serverURL.deletingLastPathComponent())
    return StdioTransport(
      serverProcessInfo: serverProcessInfo,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities)
  }

  /// Creates a sampling transport for testing sampling functionality
  public static func createSamplingTransport() -> StdioTransport {
    return createStdioTransport(serverName: "echo-sampling")
  }
}

/// HTTP test server for running Python MCP servers over HTTP
public class HTTPTestServer {
  private let process: Process
  public let serverURL: URL

  public init(streamableHTTP: Bool, scriptName: String, port: Int) throws {
    if streamableHTTP {
      let serverBaseURL = URL(string: "http://127.0.0.1:\(port)")!
      serverURL = serverBaseURL.appending(component: "mcp")
    } else {
      serverURL = URL(string: "http://127.0.0.1:\(port)/sse")!
    }

    let scriptURL = Bundle.module.url(
      forResource: scriptName,
      withExtension: "py", subdirectory: "mcp-servers")!
    let uvPath =
      ProcessInfo.processInfo.environment["UV_PATH"] ?? "\(NSHomeDirectory())/.local/bin/uv"

    process = Process()
    process.executableURL = URL(filePath: uvPath)
    process.arguments = [
      "run",
      "-qq",
      scriptURL.lastPathComponent,
      "-p",
      "\(port)",
    ]
    process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
    process.terminationHandler = { process in
      if case .uncaughtSignal = process.terminationReason {
        Issue.record("Process terminated with status: \(process.terminationStatus)")
      }
    }

    // Capture stdout and stderr
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()

    var data = Data()
    let fileHandle = errorPipe.fileHandleForReading
    let startTime = Date()
    let timeout: TimeInterval = 5.0

    while Date().timeIntervalSince(startTime) < timeout {
      let availableData = fileHandle.availableData
      if availableData.isEmpty {
        Thread.sleep(forTimeInterval: 0.01)
        continue
      }
      data.append(availableData)
      let serverBaseURL = streamableHTTP ? "http://127.0.0.1:\(port)" : "http://127.0.0.1:\(port)"
      if let contents = String(data: data, encoding: .utf8),
        contents.contains(serverBaseURL)
      {
        Thread.sleep(forTimeInterval: 0.01)
        return
      }
    }

    Issue.record(
      "Server failed to start within \(timeout) seconds. stderr: \(String(data: data, encoding: .utf8) ?? "<empty>")"
    )
  }

  public func createTransport(customConfiguration: URLSessionConfiguration? = nil)
    -> StreamableHTTPTransport
  {
    let sessionConfiguration =
      customConfiguration
      ?? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3600
        return config
      }()

    return StreamableHTTPTransport(
      serverURL: serverURL,
      urlSessionConfiguration: sessionConfiguration,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities,
      encoder: TestFixtures.jsonEncoder
    )
  }

  public func terminate() {
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
  }

  deinit {
    terminate()
  }
}

/// Records issues for non-successful transport responses to help with debugging test failures.
func recordErrorsForNonSuccessfulResponse(_ response: TransportResponse) {
  switch response {
  case .successfulRequest:
    break
  case let .failedRequest(request: request, error: error):
    Issue.record("Request \(request) failed: \(error)")
  case let .serverNotification(notification):
    Issue.record("Unexpected notification: \(notification.method)")
  case let .serverRequest(request):
    Issue.record("Unexpected server request: \(request.method)")
  case let .serverError(error):
    Issue.record("Unexpected server error: \(error)")
  case let .decodingError(request: request, error: error, data: _):
    Issue.record("Request \(String(reflecting: request)) failed with decoding error: \(error)")
  }
}

/// Executes a task with a configurable timeout interval and records an issue when the timeout is reached.
///
/// - Parameters:
///   - timeout: The timeout interval in seconds (default: 5.0)
///   - timeoutMessage: The message to record when timeout is reached
///   - defaultValue: The value to return when timeout occurs
///   - operation: The async operation to execute
/// - Returns: The result of the operation or the default value on timeout
func withTimeout<T: Sendable>(
  _ timeout: TimeInterval = 5.0,
  timeoutMessage: String,
  defaultValue: T,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      try await operation()
    }
    group.addTask {
      try await Task.sleep(for: .seconds(timeout))
      if Task.isCancelled { return defaultValue }
      Issue.record("Timeout: \(timeoutMessage)")
      return defaultValue
    }
    let result = try await group.next() ?? defaultValue
    group.cancelAll()
    return result
  }
}
