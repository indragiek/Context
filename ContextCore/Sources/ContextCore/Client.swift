// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AsyncAlgorithms
import Foundation
import os

/// Protocol for handling sampling requests from the server.
public protocol SamplingHandler: Sendable {
  /// Handle a sampling request from the server and return a response.
  ///
  /// - Parameter request: The sampling request from the server.
  /// - Returns: The sampling response to send back to the server.
  /// - Throws: An error if the sampling request cannot be handled.
  func sample(_ request: CreateMessageRequest) async throws -> CreateMessageResponse.Result
}

/// A log message emitted by the server.
public struct ServerLog: Sendable {
  /// The severity of this log message.
  public let level: LoggingLevel?

  /// An optional name of the logger issuing this message.
  public let logger: String?

  /// The data to be logged, such as a string message or an object.
  /// Any JSON serializable type is allowed here.
  public let data: JSONValue
}

// Errors thrown by the MCP client.
public enum ClientError: Error, LocalizedError {
  /// Thrown when a request sent by the client fails and the server returns an error.
  case requestFailed(request: any JSONRPCRequest, error: JSONRPCError)

  /// Thrown when the response received for a request is invalid.
  case requestInvalidResponse(request: any JSONRPCRequest, error: Error, data: Data)

  /// Thrown when a request times out. This happens when a response is not received within
  /// the configured `Client.requestTimeout`.
  case requestTimedOut(request: any JSONRPCRequest)

  /// Thrown when an in-flight request is cancelled.
  case requestCancelled(id: JSONRPCRequestID)

  /// Thrown when attempting to send a request without being connected to the server.
  case notConnected

  /// Thrown when the server doesn't support a capability
  case capabilityNotSupported(String)

  /// Thrown when no pending request exists for a given ID
  case noPendingRequest(id: JSONRPCRequestID)

  /// Thrown when an unsupported notification is received
  case unsupportedNotification(method: String)

  /// Thrown when a server request has an unexpected type
  case unexpectedRequestType(method: String, expectedType: String)

  public var errorDescription: String? {
    switch self {
    case let .requestFailed(request, error):
      return "Request '\(request.method)' failed: \(error.error.message)"
    case let .requestInvalidResponse(request, error, _):
      return "Invalid response for request '\(request.method)': \(error.localizedDescription)"
    case let .requestTimedOut(request):
      return "Request '\(request.method)' timed out"
    case let .requestCancelled(id):
      return "Request with ID '\(id)' was cancelled"
    case .notConnected:
      return "Client is not connected to server"
    case let .capabilityNotSupported(capability):
      return "Server doesn't support capability: \(capability)"
    case let .noPendingRequest(id):
      return "No pending request for ID \(id)"
    case let .unsupportedNotification(method):
      return "Received unsupported notification: \(method)"
    case let .unexpectedRequestType(method, expectedType):
      return "Expected request of type \(expectedType) for method \(method)"
    }
  }
}

public actor Client {
  public enum ConnectionState: Sendable {
    case disconnected
    case disconnecting
    case connected
    case connecting
  }

  /// The maximum duration to wait (in seconds) for a request to return a response.
  /// Defaults to 2 minutes.
  public var requestTimeout: Int = 120

  /// The capabilities supported by the server.
  /// This property is not populated until `connect()` has been called.
  public private(set) var serverCapabilities: ServerCapabilities?

  /// The name and version of the server.
  /// This property is not populated until `connect()` has been called.
  public private(set) var serverInfo: Implementation?

  /// The protocol version supported by the server.
  /// This property is not populated until `connect()` has been called.
  public private(set) var serverProtocolVersion: String?

  /// Stream of connection state updates.
  public var connectionState = AsyncChannel<ConnectionState>()

  /// The current connection state of the client.
  public var currentConnectionState: ConnectionState {
    _connectionState
  }

  /// Stream of errors returned by the server that are *not* a response to a request sent by
  /// the client. These errors are returned directly by the corresponding request APIs.
  public var errors = AsyncChannel<JSONRPCError>()

  /// Stream of all errors that occur within the client, including transport errors,
  /// protocol errors, and other internal errors.
  public var streamErrors = AsyncChannel<Error>()

  /// Stream of logs emitted by the server.
  public var logs = AsyncChannel<ServerLog>()

  /// Whether the list of prompts on the server has changed. This is set in response to
  /// `notifications/prompts/list_changed` being sent by the server. The consumer can inspect
  /// this property and call `listPrompts` to fetch an updated list of prompts.
  ///
  /// Once updated prompts have been fetched, this property is set back to `false`.
  public private(set) var promptListChanged = false

  /// Whether the list of resources on the server has changed. This is set in response to
  /// `notifications/resources/list_changed` being sent by the server. The consumer can inspect
  /// this property and call `listResources` to fetch an updated list of resources.
  ///
  /// Once updated resources have been fetched, this property is set back to `false`.
  public private(set) var resourceListChanged = false

  /// Whether the list of tools on the server has changed. This is set in response to
  /// `notifications/tools/list_changed` being sent by the server. The consumer can inspect
  /// this property and call `listTools` to fetch an updated list of tools.
  ///
  /// Once updated tools have been fetched, this property is set back to `false`.
  public private(set) var toolListChanged = false

  /// The list of filesystem roots that the client exposes to the server.
  /// This defaults to an empty array.
  public var roots: [Root] = [] {
    didSet {
      if roots != oldValue {
        Task {
          await sendRootsListChangedNotification()
        }
      }
    }
  }

  /// The transport used by this client.
  public let transport: any Transport

  private let logger: Logger
  private let idGenerator: Transport.IDGenerator
  private let samplingHandler: (any SamplingHandler)?

  private var _connectionState = ConnectionState.disconnected
  private var responseHandlerTask: Task<Void, Never>?
  private var logHandlerTask: Task<Void, Never>?
  private var connectionStateHandlerTask: Task<Void, Never>?
  private var requestChannels = [
    JSONRPCRequestID: AsyncThrowingChannel<any JSONRPCResponse, Error>
  ]()
  private var resourceSubscriptions = [
    String: AsyncThrowingChannel<ResourceUpdatedNotification, Error>
  ]()

  // MARK: - Public API

  public init(
    transport: any Transport, samplingHandler: (any SamplingHandler)? = nil,
    logger: Logger = Logger(subsystem: "com.indragie.Context", category: "MCPClient"),
    idGenerator: @escaping Transport.IDGenerator = { .string(UUID().uuidString) }
  ) {
    self.transport = transport
    self.samplingHandler = samplingHandler
    self.logger = logger
    self.idGenerator = idGenerator
  }

  public func connect() async throws {
    switch _connectionState {
    case .disconnected, .disconnecting:
      break
    case .connected:
      logger.debug("Already connected to server")
      return
    case .connecting:
      logger.debug("Already connecting to server")
      return
    }

    setupConnectionStateHandler()
    updateConnectionState(.connecting)

    do {
      logger.debug("Starting transport")
      try await transport.start()
    } catch let error {
      logAndStreamError("Failed to start transport", error: error)
      updateConnectionState(.disconnected)
      throw error
    }

    setupResponseHandler()
    setupLogHandler()

    logger.info("Connecting to server")
    do {
      logger.debug("Initializing connection")
      let initResponse = try await transport.initialize(idGenerator: idGenerator)
      serverInfo = initResponse.serverInfo
      serverCapabilities = initResponse.capabilities
      serverProtocolVersion = initResponse.protocolVersion

      logger.info(
        "Connected to server \(initResponse.serverInfo.name) \(initResponse.serverInfo.version). protocolVersion: \(initResponse.protocolVersion), capabilities: \(String(reflecting: initResponse.capabilities))"
      )
    } catch let error {
      logAndStreamError("Failed to connect to server", error: error)
      updateConnectionState(.disconnected)
      throw error
    }
  }

  public func disconnect() async throws {
    switch _connectionState {
    case .connected, .connecting:
      break
    case .disconnected:
      logger.debug("Already disconnected from server")
      return
    case .disconnecting:
      logger.debug("Already disconnecting from server")
      return
    }

    updateConnectionState(.disconnecting)
    try await transport.close()

    responseHandlerTask?.cancel()
    responseHandlerTask = nil

    logHandlerTask?.cancel()
    logHandlerTask = nil

    requestChannels.removeAll()

    for (_, channel) in resourceSubscriptions {
      channel.finish()
    }
    resourceSubscriptions.removeAll()
  }

  // MARK: - Prompts

  /// List available prompt templates from the server.
  ///
  /// - Parameters:
  ///   - cursor: Optional pagination cursor for fetching additional results.
  /// - Returns: A list of available prompt templates and a cursor for pagination if supported.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support prompts,
  ///   or other transport-related errors.
  public func listPrompts(cursor: String? = nil) async throws -> (
    prompts: [Prompt], nextCursor: String?
  ) {
    try checkCapability { $0.prompts }
    let request = ListPromptsRequest(id: idGenerator(), cursor: cursor)
    let response = try await sendRequestAndWaitForResponse(request: request)
    promptListChanged = false
    return (prompts: response.result.prompts, nextCursor: response.result.nextCursor)
  }

  /// Get a specific prompt template from the server.
  ///
  /// - Parameters:
  ///   - name: The name of the prompt template to retrieve.
  ///   - arguments: Optional arguments to customize the prompt.
  /// - Returns: The prompt description and messages.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support prompts,
  ///   or other transport-related errors.
  public func getPrompt(name: String, arguments: [String: String]? = nil) async throws -> (
    description: String?, messages: [PromptMessage]
  ) {
    try checkCapability { $0.prompts }
    let request = GetPromptRequest(id: idGenerator(), name: name, arguments: arguments)
    let response = try await sendRequestAndWaitForResponse(request: request)
    return (description: response.result.description, messages: response.result.messages)
  }

  // MARK: - Resources

  /// List available resources from the server.
  ///
  /// - Parameters:
  ///   - cursor: Optional pagination cursor for fetching additional results.
  /// - Returns: A list of available resources and a cursor for pagination if supported.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support resources,
  ///   or other transport-related errors.
  public func listResources(cursor: String? = nil) async throws -> (
    resources: [Resource], nextCursor: String?
  ) {
    try checkCapability { $0.resources }
    let request = ListResourcesRequest(id: idGenerator(), cursor: cursor)
    let response = try await sendRequestAndWaitForResponse(request: request)
    resourceListChanged = false
    return (resources: response.result.resources, nextCursor: response.result.nextCursor)
  }

  /// Read a specific resource from the server.
  ///
  /// - Parameters:
  ///   - uri: The URI of the resource to read.
  /// - Returns: The resource content.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support resources,
  ///   or other transport-related errors.
  public func readResource(uri: String) async throws -> [EmbeddedResource] {
    try checkCapability { $0.resources }
    let request = ReadResourceRequest(id: idGenerator(), uri: uri)
    let response = try await sendRequestAndWaitForResponse(request: request)
    return response.result.contents
  }

  /// Subscribe to updates for a specific resource.
  ///
  /// - Parameters:
  ///   - uri: The URI of the resource to subscribe to.
  /// - Returns: An AsyncThrowingChannel that yields ResourceUpdatedNotification when the resource changes.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support resource subscriptions,
  ///   or other transport-related errors.
  public func subscribeToResource(uri: String) async throws -> AsyncThrowingChannel<
    ResourceUpdatedNotification, Error
  > {
    guard let resources = serverCapabilities?.resources, let subscribe = resources.subscribe,
      subscribe
    else {
      throw ClientError.capabilityNotSupported("resource subscriptions")
    }

    let request = SubscribeRequest(id: idGenerator(), uri: uri)
    _ = try await sendRequestAndWaitForResponse(request: request)

    let channel = AsyncThrowingChannel<ResourceUpdatedNotification, Error>()
    resourceSubscriptions[uri] = channel
    return channel
  }

  /// Unsubscribe from updates for a specific resource.
  ///
  /// - Parameters:
  ///   - uri: The URI of the resource to unsubscribe from.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support resource subscriptions,
  ///   or other transport-related errors.
  public func unsubscribeFromResource(uri: String) async throws {
    guard let resources = serverCapabilities?.resources, let subscribe = resources.subscribe,
      subscribe
    else {
      throw ClientError.capabilityNotSupported("resource subscriptions")
    }

    let request = UnsubscribeRequest(id: idGenerator(), uri: uri)
    _ = try await sendRequestAndWaitForResponse(request: request)

    if let channel = resourceSubscriptions.removeValue(forKey: uri) {
      channel.finish()
    }
  }

  /// List available resource templates from the server.
  ///
  /// - Parameters:
  ///   - cursor: Optional pagination cursor for fetching additional results.
  /// - Returns: A list of available resource templates and a cursor for pagination if supported.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support resources,
  ///   or other transport-related errors.
  public func listResourceTemplates(cursor: String? = nil) async throws -> (
    resourceTemplates: [ResourceTemplate], nextCursor: String?
  ) {
    try checkCapability { $0.resources }
    let request = ListResourceTemplatesRequest(id: idGenerator(), cursor: cursor)
    let response = try await sendRequestAndWaitForResponse(request: request)
    return (
      resourceTemplates: response.result.resourceTemplates, nextCursor: response.result.nextCursor
    )
  }

  // MARK: - Tools

  /// List available tools from the server.
  ///
  /// - Parameters:
  ///   - cursor: Optional pagination cursor for fetching additional results.
  /// - Returns: A list of available tools and a cursor for pagination if supported.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support tools,
  ///   or other transport-related errors.
  public func listTools(cursor: String? = nil) async throws -> (tools: [Tool], nextCursor: String?)
  {
    try checkCapability { $0.tools }
    let request = ListToolsRequest(id: idGenerator(), cursor: cursor)
    let response = try await sendRequestAndWaitForResponse(request: request)
    toolListChanged = false
    return (tools: response.result.tools, nextCursor: response.result.nextCursor)
  }

  /// Call a specific tool provided by the server.
  ///
  /// - Parameters:
  ///   - name: The name of the tool to call.
  ///   - arguments: Optional arguments to pass to the tool.
  /// - Returns: The content returned by the tool and whether an error occurred.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support tools,
  ///   or other transport-related errors.
  public func callTool(name: String, arguments: [String: JSONValue]? = nil) async throws -> (
    content: [Content], isError: Bool
  ) {
    try checkCapability { $0.tools }
    let request = CallToolRequest(id: idGenerator(), name: name, arguments: arguments)
    let response = try await sendRequestAndWaitForResponse(request: request)
    return (content: response.result.content, isError: response.result.isError ?? false)
  }

  // MARK: - Ping

  /// Send a ping request to the server to check if it's still responsive.
  ///
  /// - Throws: Transport-related errors if the ping fails.
  public func ping() async throws {
    let request = PingRequest(id: idGenerator())
    _ = try await sendRequestAndWaitForResponse(request: request)
  }

  // MARK: - Completion

  /// Request completion suggestions from the server for a specific argument.
  ///
  /// - Parameters:
  ///   - ref: A reference to a prompt or resource.
  ///   - argumentName: The name of the argument to complete.
  ///   - argumentValue: The current value of the argument to use for completion matching.
  /// - Returns: Completion suggestions including values, total count, and whether more are available.
  /// - Throws: A `ClientError.unsupportedCapability` if the server doesn't support completions,
  ///   or other transport-related errors.
  public func complete(ref: Reference, argumentName: String, argumentValue: String) async throws
    -> (values: [String], total: Int?, hasMore: Bool?)
  {
    try checkCapability { $0.completions }
    let argument = CompleteRequest.Argument(name: argumentName, value: argumentValue)
    let request = CompleteRequest(id: idGenerator(), ref: ref, argument: argument)
    let response = try await sendRequestAndWaitForResponse(request: request)
    let completion = response.result.completion
    return (values: completion.values, total: completion.total, hasMore: completion.hasMore)
  }

  // MARK: - Roots

  /// Set the filesystem roots that the client exposes to the server.
  ///
  /// - Parameter roots: The list of filesystem roots to expose to the server.
  public func setRoots(_ roots: [Root]) {
    self.roots = roots
  }

  // MARK: - Internal

  private func checkCapability<T>(check: (ServerCapabilities) -> T?) throws {
    guard let serverCapabilities = serverCapabilities else {
      throw ClientError.notConnected
    }
    let capability = check(serverCapabilities)
    if capability == nil {
      throw ClientError.capabilityNotSupported("\(T.self)".lowercased())
    }
  }

  private func cancelRequest(id: JSONRPCRequestID, reason: String? = nil) async throws {
    requestChannels[id]?.fail(ClientError.requestCancelled(id: id))
    requestChannels.removeValue(forKey: id)
    let notification = CancelledNotification(requestId: id, reason: reason)
    try await transport.send(notification: notification)
  }

  private func sendRequestAndWaitForResponse<T: JSONRPCRequest>(request: T) async throws
    -> T.Response
  {
    let channel = AsyncThrowingChannel<any JSONRPCResponse, Error>()
    logger.info("Sending request \(String(reflecting: request), privacy: .private)")
    requestChannels[request.id] = channel
    try await transport.send(request: request)

    let timeout = self.requestTimeout
    let logger = self.logger

    return try await withTaskCancellationHandler(
      operation: {
        return try await withThrowingTaskGroup(of: T.Response.self) { group in
          group.addTask {
            guard let response = try await channel.first(where: { _ in true }) as? T.Response else {
              logger.error("Channel did not send any response -- this might be a timeout")
              throw ClientError.requestTimedOut(request: request)
            }
            return response
          }
          group.addTask {
            await Task.yield()
            try await Task.sleep(for: .seconds(timeout))
            throw ClientError.requestTimedOut(request: request)
          }
          defer { group.cancelAll() }
          return try await group.next()!
        }
      },
      onCancel: {
        Task {
          do {
            try await cancelRequest(id: request.id)
          } catch {
            await self.logAndStreamError("Failed to cancel request \(request.id)", error: error)
          }
        }
      })
  }

  private func updateConnectionState(_ state: ConnectionState) {
    if _connectionState == state { return }
    logger.info("Updating connection state to \(String(reflecting: state))")
    _connectionState = state
    Task { await connectionState.send(state) }
  }

  private func setupConnectionStateHandler() {
    guard connectionStateHandlerTask == nil else {
      return
    }
    connectionStateHandlerTask = Task {
      do {
        for try await state in try await transport.receiveConnectionState() {
          if Task.isCancelled { break }
          switch state {
          case .connected:
            updateConnectionState(.connected)
          case .disconnected:
            updateConnectionState(.disconnected)
          }
        }
      } catch let error {
        self.logAndStreamError("Error receiving connection state update", error: error)
      }
    }
  }

  private func setupLogHandler() {
    if let logHandlerTask = logHandlerTask {
      logHandlerTask.cancel()
    }
    logHandlerTask = Task {
      do {
        try await withThrowingTaskGroup(of: Void.self) { group in
          for try await line in try await transport.receiveLogs() {
            if Task.isCancelled { break }
            handleStderrLog(line, group: &group)
          }
        }
      } catch let error {
        self.logAndStreamError("Error receiving logs", error: error)
      }
    }
  }

  private func setupResponseHandler() {
    if let responseHandlerTask = responseHandlerTask {
      responseHandlerTask.cancel()
    }
    responseHandlerTask = Task {
      do {
        try await withThrowingTaskGroup(of: Void.self) { group in
          for try await response in try await transport.receive() {
            if Task.isCancelled { break }
            logger.info("Received response: \(String(reflecting: response), privacy: .private)")
            handleTransportResponse(response, group: &group)
          }
        }
      } catch let error {
        self.logAndStreamError("Error receiving response", error: error)
      }
    }
  }

  private func handleTransportResponse(
    _ response: TransportResponse, group: inout ThrowingTaskGroup<Void, Error>
  ) {
    switch response {
    case let .successfulRequest(request: request, response: response):
      handleSuccessfulRequest(request: request, response: response, group: &group)
    case let .failedRequest(request: request, error: error):
      handleFailedRequest(request: request, error: error)
    case let .decodingError(request: request, error: error, data: data):
      handleDecodingError(request: request, error: error, data: data)
    case let .serverNotification(notification):
      handleNotification(notification, group: &group)
    case let .serverRequest(request):
      handleServerRequest(request, group: &group)
    case let .serverError(error):
      handleError(error, group: &group)
    }
  }

  private func handleSuccessfulRequest(
    request: any JSONRPCRequest, response: any JSONRPCResponse,
    group: inout ThrowingTaskGroup<Void, Error>
  ) {
    if request.method == "initialize" {
      logger.debug(
        "Client received response to initialize request; this will be handled by the transport")
      return
    }

    if let channel = requestChannels[request.id] {
      group.addTask {
        await channel.send(response)
        channel.finish()
      }
      requestChannels.removeValue(forKey: request.id)
    } else {
      let error = ClientError.noPendingRequest(id: request.id)
      logAndStreamError("No pending request", error: error)
    }
  }

  private func handleFailedRequest(request: any JSONRPCRequest, error: JSONRPCError) {
    if request.method == "initialize" {
      logger.debug(
        "Client received response to initialize request; this will be handled by the transport")
      return
    }

    if let channel = requestChannels[request.id] {
      channel.fail(ClientError.requestFailed(request: request, error: error))
      requestChannels.removeValue(forKey: request.id)
    } else {
      let error = ClientError.noPendingRequest(id: request.id)
      logAndStreamError("No pending request", error: error)
    }
  }

  private func handleDecodingError(request: (any JSONRPCRequest)?, error: Error, data: Data) {
    guard let request = request else { return }

    if let channel = requestChannels[request.id] {
      channel.fail(ClientError.requestInvalidResponse(request: request, error: error, data: data))
      requestChannels.removeValue(forKey: request.id)
    } else {
      let error = ClientError.noPendingRequest(id: request.id)
      logAndStreamError("No pending request", error: error)
    }
  }

  private func handleNotification(
    _ notification: any JSONRPCNotification, group: inout ThrowingTaskGroup<Void, Error>
  ) {
    switch notification {
    case let logMessage as LoggingMessageNotification:
      handleLogMessage(logMessage, group: &group)
    case let stderrLogMessage as StderrNotification:
      if let content = stderrLogMessage.params?.content {
        handleStderrLog(content, group: &group)
      }
    case is PromptListChangedNotification:
      logger.info("Prompt list changed")
      promptListChanged = true
    case is ResourceListChangedNotification:
      logger.info("Resource list changed")
      resourceListChanged = true
    case is ToolListChangedNotification:
      logger.info("Tool list changed")
      toolListChanged = true
    case let cancelled as CancelledNotification:
      handleCancelledNotification(cancelled)
    case let resourceUpdated as ResourceUpdatedNotification:
      handleResourceUpdatedNotification(resourceUpdated, group: &group)
    case is ProgressNotification:
      logger.info("Progress notifications are not yet supported")
    default:
      let error = ClientError.unsupportedNotification(method: notification.method)
      logAndStreamError("Received unsupported notification", error: error)
    }
  }

  private func handleLogMessage(
    _ logMessage: LoggingMessageNotification, group: inout ThrowingTaskGroup<Void, Error>
  ) {
    group.addTask {
      if let params = logMessage.params {
        await self.logs.send(
          ServerLog(
            level: params.level,
            logger: params.logger,
            data: params.data
          ))
      }
    }
  }

  private func handleStderrLog(_ log: String, group: inout ThrowingTaskGroup<Void, Error>) {
    group.addTask {
      await self.logs.send(ServerLog(level: nil, logger: "stderr", data: .string(log)))
    }
  }

  private func handleCancelledNotification(_ cancelled: CancelledNotification) {
    guard let id = cancelled.params?.requestId else {
      logger.warning("Received cancelled notification without requestId")
      return
    }
    if let channel = requestChannels[id] {
      channel.fail(ClientError.requestCancelled(id: id))
      requestChannels.removeValue(forKey: id)
      logger.info("Request \(id) cancelled with reason: \(cancelled.params?.reason ?? "<none>")")
    } else {
      let error = ClientError.noPendingRequest(id: id)
      logAndStreamError("No pending request", error: error)
    }
  }

  private func handleResourceUpdatedNotification(
    _ resourceUpdated: ResourceUpdatedNotification, group: inout ThrowingTaskGroup<Void, Error>
  ) {
    guard let uri = resourceUpdated.params?.uri else {
      logger.warning("Received resource updated notification without URI")
      return
    }
    if let channel = resourceSubscriptions[uri] {
      group.addTask {
        await channel.send(resourceUpdated)
      }
    } else {
      logger.warning("Received resource update notification for unsubscribed URI: \(uri)")
    }
  }

  private func handleServerRequest(
    _ request: any JSONRPCRequest, group: inout ThrowingTaskGroup<Void, Error>
  ) {
    logger.info("Received server request: \(request.method)")

    switch request.method {
    case "sampling/createMessage":
      guard let samplingRequest = request as? CreateMessageRequest else {
        let error = ClientError.unexpectedRequestType(
          method: request.method, expectedType: "CreateMessageRequest")
        logAndStreamError("Unexpected request type", error: error)
        return
      }
      group.addTask {
        await self.handleSamplingRequest(samplingRequest)
      }
    case "roots/list":
      guard let rootsRequest = request as? ListRootsRequest else {
        let error = ClientError.unexpectedRequestType(
          method: request.method, expectedType: "ListRootsRequest")
        logAndStreamError("Unexpected request type", error: error)
        return
      }
      group.addTask {
        await self.handleRootsListRequest(rootsRequest)
      }
    case "ping":
      guard let pingRequest = request as? PingRequest else {
        let error = ClientError.unexpectedRequestType(
          method: request.method, expectedType: "PingRequest")
        logAndStreamError("Unexpected request type", error: error)
        return
      }
      group.addTask {
        await self.handlePingRequest(pingRequest)
      }
    default:
      logger.warning("Received unsupported server request: \(request.method)")
    }
  }

  private func handleSamplingRequest(_ request: CreateMessageRequest) async {
    guard let samplingHandler = samplingHandler else {
      logger.warning("Received sampling request but no sampling handler is configured")
      // Send an error response
      let errorResponse = JSONRPCError(
        error: JSONRPCError.ErrorBody(
          code: -32601,
          message: "Sampling not supported",
          data: nil
        ),
        id: request.id
      )
      do {
        try await transport.send(error: errorResponse)
      } catch {
        self.logAndStreamError("Failed to send error response for sampling request", error: error)
      }
      return
    }

    do {
      let result = try await samplingHandler.sample(request)
      let response = CreateMessageResponse(
        id: request.id, role: result.role, content: result.content, model: result.model,
        stopReason: result.stopReason)
      try await transport.send(response: response)
      logger.info("Successfully handled sampling request")
    } catch {
      self.logAndStreamError("Failed to handle sampling request", error: error)
      let errorResponse = JSONRPCError(
        error: JSONRPCError.ErrorBody(
          code: -32603,
          message: "Internal error",
          data: JSONValue.string(error.localizedDescription)
        ),
        id: request.id
      )
      do {
        try await transport.send(error: errorResponse)
      } catch {
        self.logAndStreamError("Failed to send error response for sampling request", error: error)
      }
    }
  }

  private func handleRootsListRequest(_ request: ListRootsRequest) async {
    logger.info("Handling roots/list request")
    do {
      let response = ListRootsResponse(id: request.id, roots: roots)
      try await transport.send(response: response)
      logger.info("Successfully handled roots/list request")
    } catch {
      self.logAndStreamError("Failed to handle roots/list request", error: error)
      let errorResponse = JSONRPCError(
        error: JSONRPCError.ErrorBody(
          code: -32603,
          message: "Internal error",
          data: JSONValue.string(error.localizedDescription)
        ),
        id: request.id
      )
      do {
        try await transport.send(error: errorResponse)
      } catch {
        self.logAndStreamError("Failed to send error response for roots/list request", error: error)
      }
    }
  }

  private func handlePingRequest(_ request: PingRequest) async {
    logger.info("Handling ping request from server")
    do {
      let response = PingResponse(id: request.id)
      try await transport.send(response: response)
      logger.info("Successfully responded to ping request")
    } catch {
      self.logAndStreamError("Failed to respond to ping request", error: error)
    }
  }

  private func sendRootsListChangedNotification() async {
    guard _connectionState == .connected else {
      logger.debug("Not sending roots list changed notification because client is not connected")
      return
    }

    do {
      let notification = RootsListChangedNotification()
      try await transport.send(notification: notification)
      logger.info("Sent roots list changed notification")
    } catch {
      logAndStreamError("Failed to send roots list changed notification", error: error)
    }
  }

  private func handleError(_ error: JSONRPCError, group: inout ThrowingTaskGroup<Void, Error>) {
    group.addTask {
      await self.errors.send(error)
    }
  }

  /// Log an error and send it to the streamErrors channel.
  private func logAndStreamError(_ message: String, error: Error) {
    logger.error("\(message): \(error)")
    Task {
      await streamErrors.send(error)
    }
  }

}
