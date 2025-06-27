// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AsyncAlgorithms
import Foundation
import System
import os

/// Errors thrown by `StdioTransport`
public enum StdioTransportError: Error, LocalizedError, Equatable {
  /// Thrown when the server closes stdout, indicating that no more messages
  /// will be sent by the server. Contains the stderr output if available.
  case serverClosedOutputStream(String)

  /// Thrown when a message contains embedded newlines, which is not allowed by the spec.
  case embeddedNewlinesNotAllowed

  /// Thrown when the buffer size exceeds the maximum allowed limit (128MB)
  case bufferLimitExceeded

  /// Thrown when a system I/O error occurs
  case ioError(Errno)

  public var errorDescription: String? {
    switch self {
    case .serverClosedOutputStream(let stderr):
      if stderr.isEmpty {
        return "Server closed the output stream unexpectedly"
      } else {
        return stderr
      }
    case .embeddedNewlinesNotAllowed:
      return "Message contains embedded newlines, which violates the MCP stdio protocol"
    case .bufferLimitExceeded:
      return "Buffer size exceeded the maximum allowed limit (128MB)"
    case .ioError(let errno):
      return "I/O error: \(errno.localizedDescription)"
    }
  }

  public var failureReason: String? {
    switch self {
    case .serverClosedOutputStream:
      return "The server process terminated or closed its standard output"
    case .embeddedNewlinesNotAllowed:
      return
        "The MCP protocol requires that messages do not contain embedded newline characters"
    case .bufferLimitExceeded:
      return "The accumulated buffer size exceeded 128MB without finding complete messages"
    case .ioError(let errno):
      return errno.localizedDescription
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .serverClosedOutputStream(let stderr):
      if stderr.isEmpty {
        return "Check if the server process crashed or was terminated unexpectedly"
      } else {
        return
          "Check the stderr output for error details. The server process may have encountered an error."
      }
    case .embeddedNewlinesNotAllowed:
      return "Remove any newline characters from the message content before sending"
    case .bufferLimitExceeded:
      return "Ensure the server is sending properly formatted messages with newline delimiters"
    case .ioError:
      return "Check system logs and ensure the process has proper permissions"
    }
  }

  public static func == (lhs: StdioTransportError, rhs: StdioTransportError) -> Bool {
    switch (lhs, rhs) {
    case (.serverClosedOutputStream(let a), .serverClosedOutputStream(let b)):
      return a == b
    case (.embeddedNewlinesNotAllowed, .embeddedNewlinesNotAllowed):
      return true
    case (.bufferLimitExceeded, .bufferLimitExceeded):
      return true
    case (.ioError(let a), .ioError(let b)):
      return a.rawValue == b.rawValue
    default:
      return false
    }
  }
}

/// Implements the MCP stdio transport as documented in:
/// https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#stdio
public actor StdioTransport: Transport {
  /// Configuration for starting the MCP server process.
  public struct ServerProcessInfo {
    /// The URL to the server executable. This must be a local file URL.
    public let executableURL: URL

    /// The arguments to pass when starting the server process.
    public let arguments: [String]?

    /// Environment variables to set when starting the server process.
    public let environment: [String: String]?

    /// The current directory to start the server process in.
    public let currentDirectoryURL: URL?

    public init(
      executableURL: URL, arguments: [String]? = nil, environment: [String: String]? = nil,
      currentDirectoryURL: URL? = nil
    ) {
      self.executableURL = executableURL
      self.arguments = arguments
      self.environment = environment
      self.currentDirectoryURL = currentDirectoryURL
    }
  }

  private let serverProcessInfo: ServerProcessInfo
  private let clientInfo: Implementation
  private let clientCapabilities: ClientCapabilities
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let logger: Logger

  private var process: Process?
  private var pendingRequests = [JSONRPCRequestID: any JSONRPCRequest]()
  private var inputPipe: Pipe?
  private var internalResponseChannel: AsyncChannel<TransportResponse>?
  private var responseChannel: AsyncThrowingChannel<TransportResponse, Error>?
  private var logChannel: AsyncThrowingChannel<String, Error>?
  private var connectionStateChannel = AsyncThrowingChannel<TransportConnectionState, Error>()
  private var readResponsesTask: Task<Void, Error>?
  private var readLogsTask: Task<Void, Error>?
  private var stderrBuffer = ""

  /// Initializes the transport.
  ///
  /// - Parameters
  ///     - serverProcessInfo: Configuration for starting the MCP server process.
  ///     - clientInfo: The name and version of the MCP client.
  ///     - clientCapabilities: Capabilities supported by the client.
  ///     - encoder: The encoder used to encode JSON-RPC messages.
  ///     - decoder: The decoder used to decode JSON-RPC messages.
  ///     - logger: Logger used to log diagnostic information.
  ///
  public init(
    serverProcessInfo: ServerProcessInfo,
    clientInfo: Implementation,
    clientCapabilities: ClientCapabilities,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder(),
    logger: Logger = Logger(subsystem: "com.indragie.Context", category: "StdioTransport")
  ) {
    self.serverProcessInfo = serverProcessInfo
    self.clientInfo = clientInfo
    self.clientCapabilities = clientCapabilities
    self.encoder = encoder
    self.decoder = decoder
    self.logger = logger
  }

  // MARK: - Transport

  public func start() async throws {
    guard process == nil else {
      logger.debug("Called start() while process is active; no-op")
      return
    }

    // Initialize channels early to ensure they're available even if start fails
    let responseChannel = AsyncThrowingChannel<TransportResponse, Error>()
    let internalResponseChannel = AsyncChannel<TransportResponse>()
    let logChannel = AsyncThrowingChannel<String, Error>()

    // Store channels immediately to prevent crashes in initialize()
    self.responseChannel = responseChannel
    self.internalResponseChannel = internalResponseChannel
    self.logChannel = logChannel

    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    do {
      process = try await {
        let process = Process()
        process.executableURL = serverProcessInfo.executableURL
        process.arguments = serverProcessInfo.arguments
        var environment = process.environment ?? [:]
        serverProcessInfo.environment?.forEach { environment[$0] = $1 }

        // Get merged PATH from user's shell and current process
        let mergedPath = try await getMergedPath()
        environment["PATH"] = mergedPath

        process.environment = environment
        process.currentDirectoryURL = serverProcessInfo.currentDirectoryURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let logger = self.logger
        let connectionStateChannel = self.connectionStateChannel
        process.terminationHandler = { p in
          logger.info("Process exited with status code \(p.terminationStatus)")
          Task {
            await connectionStateChannel.send(.disconnected)
          }
        }

        try process.run()

        Task {
          await connectionStateChannel.send(.connected)
        }
        return process
      }()
      self.inputPipe = inputPipe
    } catch {
      // Clean up channels on failure
      responseChannel.fail(error)
      internalResponseChannel.finish()
      logChannel.fail(error)
      self.responseChannel = nil
      self.internalResponseChannel = nil
      self.logChannel = nil
      throw error
    }

    let getStderrBuffer: @Sendable () async -> String = { [weak self] in
      return await self?.flushStderrBuffer() ?? ""
    }
    readResponsesTask = Task {
      do {
        for try await data in readLines(
          fileHandle: outputPipe.fileHandleForReading, throwOnEOF: true,
          stderrBuffer: getStderrBuffer)
        {
          if Task.isCancelled { return }
          for response in try decodeAllResponses(
            data: data, requestLookupCache: &pendingRequests, logger: logger, decoder: decoder)
          {
            Task { await responseChannel.send(response) }
            Task { await internalResponseChannel.send(response) }
          }
        }
        responseChannel.finish()
      } catch let error {
        responseChannel.fail(error)
      }
    }

    readLogsTask = Task {
      do {
        for try await data in readLines(fileHandle: errorPipe.fileHandleForReading) {
          if Task.isCancelled { return }
          if let line = String(data: data, encoding: .utf8) {
            stderrBuffer += line + "\n"
            await logChannel.send(line)
          }
        }
        logChannel.finish()
      } catch let error {
        logChannel.fail(error)
      }
    }
  }

  public func initialize(idGenerator: @escaping IDGenerator) async throws
    -> InitializeResponse.Result
  {
    guard let internalResponseChannel = internalResponseChannel else {
      throw TransportError.notStarted
    }
    let initialize = InitializeRequest(
      id: idGenerator(),
      protocolVersion: MCPProtocolVersion,
      capabilities: clientCapabilities,
      clientInfo: clientInfo
    )
    try await send(request: initialize)
    let waitForResponse: (JSONRPCRequestID) async throws -> TransportResponse = {
      for await response in internalResponseChannel {
        switch response {
        case .successfulRequest(request: let r, response: _):
          if r.id == $0 {
            return response
          }
        case .failedRequest(request: let r, error: _):
          if r.id == $0 {
            return response
          }
        case .decodingError(request: let r, error: _, data: _):
          if r?.id == $0 {
            return response
          }
        case .serverNotification, .serverRequest, .serverError:
          // Skip notifications, server requests, and errors as they are not responses to our request
          continue
        }
      }
      throw TransportError.noResponse
    }
    let transportResponse = try await waitForResponse(initialize.id)
    switch transportResponse {
    case .successfulRequest(request: _, let response):
      guard let initializeResponse = response as? InitializeResponse else {
        throw TransportError.unexpectedResponse(response)
      }
      let initialized = InitializedNotification()
      try await send(notification: initialized)
      return initializeResponse.result
    case .failedRequest(request: _, let error):
      throw TransportError.initializationFailed(error)
    case .serverNotification(let notification):
      throw TransportError.unexpectedNotification(method: notification.method)
    case .serverRequest(let request):
      throw TransportError.unexpectedNotification(method: request.method)
    case .serverError(let error):
      throw TransportError.initializationFailed(error)
    case .decodingError(request: _, error: _, let data):
      throw TransportError.invalidMessage(data: data)
    }
  }

  public func send(request: any JSONRPCRequest) async throws {
    pendingRequests[request.id] = request
    do {
      try send(data: try encoder.encode(request))
    } catch {
      pendingRequests.removeValue(forKey: request.id)
      throw error
    }
  }

  public func send(notification: any JSONRPCNotification) async throws {
    try send(data: try encoder.encode(notification))
  }

  public func send(response: any JSONRPCResponse) async throws {
    try send(data: try encoder.encode(response))
  }

  public func send(error: JSONRPCError) async throws {
    try send(data: try encoder.encode(error))
  }

  public func send(batch: [JSONRPCBatchItem]) async throws {
    if batch.isEmpty {
      throw TransportError.emptyBatch
    }

    for item in batch {
      if case .request(let request) = item {
        pendingRequests[request.id] = request
      }
    }
    do {
      try send(data: try encoder.encode(batch))
    } catch {
      for item in batch {
        if case .request(let request) = item {
          pendingRequests.removeValue(forKey: request.id)
        }
      }
      throw error
    }
  }

  public func receive() async throws -> AsyncThrowingChannel<TransportResponse, Error> {
    guard let responseChannel = responseChannel else {
      throw TransportError.notStarted
    }
    return responseChannel
  }

  public func receiveLogs() async throws -> AsyncThrowingChannel<String, Error> {
    guard let logChannel = logChannel else {
      throw TransportError.notStarted
    }
    return logChannel
  }

  public func receiveConnectionState() async throws -> AsyncThrowingChannel<
    TransportConnectionState, Error
  > {
    return connectionStateChannel
  }

  public func close() async throws {
    guard let process = process else {
      logger.debug("close() called before start(); no-op")
      return
    }

    responseChannel?.finish()
    responseChannel = nil

    internalResponseChannel?.finish()
    internalResponseChannel = nil

    logChannel?.finish()
    logChannel = nil

    readResponsesTask?.cancel()
    readResponsesTask = nil

    readLogsTask?.cancel()
    readLogsTask = nil

    try inputPipe?.fileHandleForWriting.close()
    self.inputPipe = nil

    process.terminate()
    if !(await waitForProcessExit(process: process, timeout: 2.0)) {
      // If still running after SIGTERM, send SIGKILL as last resort
      kill(process.processIdentifier, SIGKILL)

      // Wait one more time, but with shorter timeout
      if !(await waitForProcessExit(process: process, timeout: 1.0)) {
        // If we get here, we've done our best to terminate the process
        logger.warning("Process \(process.processIdentifier) could not be terminated")
      }
    }
    self.process = nil
    pendingRequests.removeAll()
    stderrBuffer = ""
  }

  // MARK: - Internal

  private func flushStderrBuffer() -> String {
    let buffer = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    stderrBuffer = ""
    return buffer
  }

  /// Gets the merged PATH from the user's default shell and current process environment.
  private func getMergedPath() async throws -> String {
    var shellPaths: [String] = []
    var currentProcessPaths: [String] = []
    var allPaths = Set<String>()

    // Get user's default shell PATH
    let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    do {
      let shellProcess = Process()
      let outputPipe = Pipe()

      shellProcess.executableURL = URL(fileURLWithPath: userShell)
      // Using `env | grep '^PATH='` instead of `echo $PATH` because most shells use a colon delimiter
      // for $PATH, but fish prints it as a list with a space delimiter instead. This has consistent
      // behavior across shells.
      let pathPrefix = "PATH="
      shellProcess.arguments = ["-l", "-c", "env | grep '^\(pathPrefix)'"]
      shellProcess.standardOutput = outputPipe
      shellProcess.standardError = Pipe()

      try shellProcess.run()
      shellProcess.waitUntilExit()

      if shellProcess.terminationStatus == 0 {
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if var shellPath = String(data: data, encoding: .utf8)?.trimmingCharacters(
          in: .whitespacesAndNewlines)
        {
          if shellPath.hasPrefix(pathPrefix) {
            shellPath = String(shellPath.dropFirst(pathPrefix.count))
          }
          for path in shellPath.split(separator: ":") {
            let pathStr = String(path)
            if !allPaths.contains(pathStr) {
              shellPaths.append(pathStr)
              allPaths.insert(pathStr)
            }
          }
        }
      }
    } catch {
      logger.warning("Failed to get shell PATH: \(error)")
    }

    // Get current process's PATH
    if let currentPath = ProcessInfo.processInfo.environment["PATH"] {
      for path in currentPath.split(separator: ":") {
        let pathStr = String(path)
        if !allPaths.contains(pathStr) {
          currentProcessPaths.append(pathStr)
          allPaths.insert(pathStr)
        }
      }
    }

    let systemPaths = [
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
    ]

    var fallbackPaths: [String] = []
    for path in systemPaths {
      if !allPaths.contains(path) {
        fallbackPaths.append(path)
        allPaths.insert(path)
      }
    }

    // Combine paths: shell paths first, then current process paths, then fallback paths
    var orderedPaths: [String] = []
    orderedPaths.append(contentsOf: shellPaths)
    orderedPaths.append(contentsOf: currentProcessPaths)
    orderedPaths.append(contentsOf: fallbackPaths)

    return orderedPaths.joined(separator: ":")
  }

  private func send(data: Data) throws {
    guard let inputPipe = inputPipe else {
      throw TransportError.notStarted
    }

    // Validate that the data doesn't contain embedded newlines as required by the spec
    if data.contains(UInt8(ascii: "\n")) {
      throw StdioTransportError.embeddedNewlinesNotAllowed
    }

    var dataWithNewline = data
    dataWithNewline.append(contentsOf: [UInt8(ascii: "\n")])
    try inputPipe.fileHandleForWriting.write(contentsOf: dataWithNewline)
  }

  /// - Returns: true if the process exited, false if it timed out
  private func waitForProcessExit(process: Process, timeout: TimeInterval) async -> Bool {
    let startTime = Date()
    while process.isRunning {
      if Date().timeIntervalSince(startTime) > timeout {
        return false
      }

      try? await Task.sleep(for: .milliseconds(10))

      if Task.isCancelled {
        return false
      }
    }
    return true
  }
}

private func readLines(
  fileHandle: FileHandle, throwOnEOF: Bool = false,
  stderrBuffer: @escaping @Sendable () async -> String = { "" }
) -> AsyncThrowingStream<
  Data, Error
> {
  AsyncThrowingStream { continuation in
    var buffer = Data()
    let queue = DispatchQueue(label: "com.context.stdio.read")
    let maxBufferSize = 128 * 1024 * 1024  // 128MB limit

    // Create DispatchIO channel for the file descriptor
    let channel = DispatchIO(type: .stream, fileDescriptor: fileHandle.fileDescriptor, queue: queue)
    { error in
      if error != 0 {
        continuation.finish(throwing: StdioTransportError.ioError(Errno(rawValue: error)))
      }
    }

    // Set low water mark to 1 byte for immediate processing
    // Set high water mark to 16MB for efficient reading
    channel.setLimit(lowWater: 1)
    channel.setLimit(highWater: 16 * 1024 * 1024)

    // Read handler
    channel.read(offset: 0, length: Int.max, queue: queue) { done, data, error in
      if error != 0 {
        continuation.finish(throwing: StdioTransportError.ioError(Errno(rawValue: error)))
        return
      }

      if let data = data, !data.isEmpty {
        data.enumerateBytes { bytes, _, _ in
          buffer.append(Data(bytes))

          // Check buffer size limit
          if buffer.count > maxBufferSize {
            continuation.finish(throwing: StdioTransportError.bufferLimitExceeded)
            channel.close()
            return
          }

          // Process all complete lines in the buffer
          while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            // Extract the line (without the newline)
            let lineData = Data(buffer.prefix(upTo: newlineIndex))
            continuation.yield(lineData)
            // Remove the processed line including the newline
            buffer.removeSubrange(0...newlineIndex)
          }
        }
      }

      if done {
        // EOF reached
        if !buffer.isEmpty && !throwOnEOF {
          // Yield any remaining data
          continuation.yield(buffer)
        }

        if throwOnEOF {
          Task {
            let stderr = await stderrBuffer()
            continuation.finish(throwing: StdioTransportError.serverClosedOutputStream(stderr))
          }
        } else {
          continuation.finish()
        }

        channel.close()
      }
    }

    continuation.onTermination = { @Sendable _ in
      channel.close()
    }
  }
}
