// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AsyncAlgorithms
import Foundation
import os

/// Implements the Streamable HTTP transport as documented in
/// https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#streamable-http
///
/// This also implements backward compatibility with the older HTTP+SSE transport as documented in:
/// https://modelcontextprotocol.io/specification/2024-11-05/basic/transports#http-with-sse
public actor StreamableHTTPTransport: Transport {
  private static let defaultReconnectionTimeMs: Int = 3000
  private static let maxReconnectAttempts: Int = 10

  private let serverURL: URL
  private let urlSession: URLSession
  private let clientInfo: Implementation
  private let clientCapabilities: ClientCapabilities
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let logger: Logger
  private let responseTimeout: TimeInterval
  internal var pingInterval: TimeInterval? {
    didSet {
      guard pingInterval != oldValue else { return }
      
      if let interval = pingInterval {
        if oldValue == nil {
          logger.info("Set ping interval to \(interval)s")
        } else {
          logger.info("Updated ping interval to \(interval)s")
        }
        startPingTimer()
      } else {
        stopPingTimer()
      }
    }
  }

  private var pendingRequests = [JSONRPCRequestID: any JSONRPCRequest]()
  private var internalResponseChannel: AsyncChannel<TransportResponse>?
  private var responseChannel: AsyncThrowingChannel<TransportResponse, Error>?
  private var connectionStateChannel = AsyncThrowingChannel<TransportConnectionState, Error>()
  private var idGenerator: Transport.IDGenerator?
  private var supportsStreamableHTTPTransport = true
  private var sendEventEndpointURL: URL?
  private var lastEventID: String?
  private var reconnectAttempts = 0
  private var reconnectionTimeMs: Int = 3000
  private var sessionID: String?
  private var activeSSEConnectionCount: Int = 0
  private var consumerTasks = [Task<Void, Error>]()
  private var authorizationToken: String?
  private var negotiatedProtocolVersion: String?
  private var sseSupported: Bool = true
  private var pingTask: Task<Void, Error>?

  /// Initializes the transport for communicating with the MCP server at the
  /// specified URL.
  ///
  /// - Parameters:
  ///     - serverURL: The URL to the MCP server. This can either be a server that implements the
  ///     new Streamable HTTP transport first defined in protocol version 2025-03-26, or the old
  ///     HTTP+SSE transport defined in protocol version 2024-11-05.
  ///     - urlSessionConfiguration: The configuration for the `URLSession` that is used to send
  ///     requests to the MCP server.
  ///     - clientInfo: The name and version of the MCP client.
  ///     - clientCapabilities: Capabilities supported by the client.
  ///     - encoder: The encoder used to encode JSON-RPC messages.
  ///     - decoder: The JSON decoder used to decode all JSON responses
  ///     returned by the server.
  ///     - logger: Logger used to log diagnostic information.
  ///     - responseTimeout: Timeout in seconds for waiting for responses to requests. Defaults to 30 seconds.
  public init(
    serverURL: URL,
    urlSessionConfiguration: URLSessionConfiguration,
    clientInfo: Implementation,
    clientCapabilities: ClientCapabilities,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder(),
    logger: Logger = Logger(subsystem: "com.indragie.Context", category: "StreamableHTTPTransport"),
    responseTimeout: TimeInterval = 30.0
  ) {
    self.serverURL = serverURL
    self.urlSession = URLSession(configuration: urlSessionConfiguration)
    self.clientInfo = clientInfo
    self.clientCapabilities = clientCapabilities
    self.encoder = encoder
    self.decoder = decoder
    self.logger = logger
    self.responseTimeout = responseTimeout
  }

  /// Sets the authorization token to be used for subsequent requests.
  ///
  /// - Parameter token: The OAuth bearer token, or nil to remove authorization.
  public func setAuthorizationToken(_ token: String?) async {
    self.authorizationToken = token
  }

  // MARK: - Transport

  public func start() async throws {
    guard responseChannel == nil else {
      logger.debug("Transport already started; no-op")
      return
    }
    responseChannel = AsyncThrowingChannel<TransportResponse, Error>()
    internalResponseChannel = AsyncChannel<TransportResponse>()
  }

  public func initialize(idGenerator: @escaping Transport.IDGenerator) async throws
    -> InitializeResponse.Result
  {
    // Cache the ID generator for when initialization needs to be retried internally
    // due to session termination.
    self.idGenerator = idGenerator
    do {
      // Try sending a request to the server to see if it supports the Streamable
      // HTTP transport.
      let result = try await tryInitialize(idGenerator: idGenerator)
      consumerTasks.append(
        Task {
          do {
            logger.info("Initialized. Opening SSE stream")
            try await openSSEStream()
          } catch let error as StreamableHTTPTransportError {
            if case .sseNotSupported = error {
              logger.info("SSE not supported by server, operating in request-response mode")
              sseSupported = false
            } else {
              logger.error("Failed to open SSE stream: \(error)")
            }
          } catch let error {
            logger.error("Failed to open SSE stream: \(error)")
          }
        })
      return result
    } catch let error as StreamableHTTPTransportError {
      switch error {
      case .serverHTTPError(let response, _, _)
      where response.statusCode >= 400 && response.statusCode < 500:
        // Indicates that the Streamable HTTP transport may not be supported. Try
        // falling back to HTTP+SSE.
        supportsStreamableHTTPTransport = false
        logger.info("Opening SSE stream to retry initialization")
        try await openSSEStream()
        // If this is successful, then `sendEventEndpointURL` will be set and
        // we can retry initialization.
        return try await tryInitialize(idGenerator: idGenerator)
      default:
        throw error
      }
    }
  }

  public func send(request: any JSONRPCRequest) async throws {
    _ = try await sendHTTP(request: request)
  }

  public func send(notification: any JSONRPCNotification) async throws {
    _ = try await sendHTTP(notification: notification)
  }

  public func send(response: any JSONRPCResponse) async throws {
    _ = try await sendHTTP(response: response)
  }

  public func send(error: JSONRPCError) async throws {
    _ = try await sendHTTP(error: error)
  }

  public func send(batch: [JSONRPCBatchItem]) async throws {
    _ = try await sendHTTP(batch: batch)
  }

  public func receive() async throws -> AsyncThrowingChannel<TransportResponse, Error> {
    guard let responseChannel = responseChannel else {
      fatalError(
        "Cannot receive messages before channel is available. Make sure to call start() first")
    }
    return responseChannel
  }

  public func receiveLogs() async throws -> AsyncThrowingStream<String, Error> {
    // Network transports don't support receiving logs outside of the logging
    // specification defined in MCP:
    // https://modelcontextprotocol.io/specification/2025-03-26/server/utilities/logging
    return AsyncThrowingStream { _ in }
  }

  public func receiveConnectionState() async throws -> AsyncThrowingChannel<
    TransportConnectionState, Error
  > {
    return connectionStateChannel
  }

  public func close() async throws {
    guard let responseChannel = responseChannel,
      let internalResponseChannel = internalResponseChannel
    else {
      logger.debug("close() called before start(); no-op")
      return
    }
    if sessionID != nil, sendEventEndpointURL == nil {
      // Explicitly terminate the session
      var request = URLRequest(url: serverURL)
      request.httpMethod = "DELETE"
      setCommonMCPHeaders(on: &request)
      let (data, response) = try await urlSession.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw StreamableHTTPTransportError.invalidResponse(response)
      }

      if httpResponse.statusCode == 405 {
        // Indicates that the server does not allow clients to terminate sessions.
        logger.warning(
          "Attempted session termination but server does not allow client to terminate sessions"
        )
      } else {
        try await throwIfHTTPError(response: httpResponse, data: data)
      }
    }

    responseChannel.finish()
    self.responseChannel = nil

    internalResponseChannel.finish()
    self.internalResponseChannel = nil

    for task in consumerTasks {
      task.cancel()
    }
    consumerTasks.removeAll()
    
    stopPingTimer()
    pingInterval = nil

    pendingRequests.removeAll()
    idGenerator = nil
    sendEventEndpointURL = nil
    lastEventID = nil
    reconnectAttempts = 0
    reconnectionTimeMs = Self.defaultReconnectionTimeMs
    sessionID = nil
    negotiatedProtocolVersion = nil
    sseSupported = true  // Reset to default
    // Don't reset activeSSEConnectionCount - let cancelled tasks decrement naturally
  }

  // MARK: - Internal

  /// Sets common MCP headers on a URLRequest including session ID, authorization, and protocol version.
  /// This consolidates the header-setting logic that is used across multiple request types.
  private func setCommonMCPHeaders(on request: inout URLRequest) {
    // Set session ID if available
    if let sessionID = sessionID {
      request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
    }

    // Set authorization token if available
    if let token = authorizationToken {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // Always set protocol version (use negotiated or default)
    let protocolVersion = negotiatedProtocolVersion ?? MCPProtocolVersion
    request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
  }

  /// Attempts to initialize the session by sending an `initialize` request. Upon a successful
  /// response, extracts the session ID (if present) and sends `notifications/initialized` to
  /// the server to complete initialization.
  private func tryInitialize(idGenerator: Transport.IDGenerator) async throws
    -> InitializeResponse.Result
  {
    guard let internalResponseChannel = internalResponseChannel else {
      fatalError(
        "Cannot receive messages before channel is available. Make sure to call start() first")
    }
    let initialize = InitializeRequest(
      id: idGenerator(),
      protocolVersion: MCPProtocolVersion,
      capabilities: clientCapabilities,
      clientInfo: clientInfo
    )
    let httpResponse = try await sendHTTP(request: initialize)
    let waitForResponse: (JSONRPCRequestID) async throws -> TransportResponse = { requestID in
      try await withThrowingTaskGroup(of: TransportResponse.self) { group in
        group.addTask {
          try await Task.sleep(for: .seconds(self.responseTimeout))
          throw TransportError.timeout
        }

        group.addTask {
          for await response in internalResponseChannel {
            switch response {
            case .successfulRequest(request: let r, response: _):
              if r.id == requestID {
                return response
              }
            case .failedRequest(request: let r, error: _):
              if r.id == requestID {
                return response
              }
            case .decodingError(request: let r, error: _, data: _):
              if r?.id == requestID {
                return response
              }
            case .serverNotification, .serverRequest, .serverError:
              // Skip notifications, server requests, and errors as they are not responses to our request
              continue
            }
          }
          throw TransportError.noResponse
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
      }
    }
    let serverResponse = try await waitForResponse(initialize.id)
    switch serverResponse {
    case .successfulRequest(request: _, let response):
      guard let initializeResponse = response as? InitializeResponse else {
        throw TransportError.unexpectedResponse(response)
      }
      if let newSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
        sessionID = try validateSessionID(newSessionID)
      }
      // Check for Keep-Alive headers on initialize response
      checkForKeepAliveHeaders(in: httpResponse)
      // Store the negotiated protocol version for subsequent requests
      negotiatedProtocolVersion = initializeResponse.result.protocolVersion
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

  /// Opens an SSE (Server-Sent Event) stream with the server and passes last event ID for
  /// resumability if available. Upon success, this function will wait for the server to
  /// send the initial `endpoint` message over the SSE stream and then will consume the
  /// remainder of the stream asynchronously.
  private func openSSEStream() async throws {
    var request = URLRequest(url: serverURL)
    request.httpMethod = "GET"
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    setCommonMCPHeaders(on: &request)
    if let lastEventID = lastEventID {
      request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
      logger.debug("Reconnecting with Last-Event-ID: \(lastEventID)")
    }

    if Task.isCancelled { return }

    let (bytes, response) = try await urlSession.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw StreamableHTTPTransportError.invalidResponse(response)
    }

    if Task.isCancelled { return }

    switch httpResponse.statusCode {
    case 200:
      let contentType = try getContentType(response: httpResponse)
      if contentType != "text/event-stream" {
        throw StreamableHTTPTransportError.invalidContentType(httpResponse, contentType)
      }
      // Reset reconnect attempts as we successfully connected
      reconnectAttempts = 0
      reconnectionTimeMs = Self.defaultReconnectionTimeMs
      
      // Check for Keep-Alive header configuration
      // Check during SSE stream setup to get Keep-Alive timeout settings
      checkForKeepAliveHeaders(in: httpResponse)
      
      try await consumeSSEStream(bytes: bytes, waitUntilEndpointEvent: true)
    case 405:
      // Server doesn't support SSE - this is a valid response, not an error to retry
      sseSupported = false
      logger.info("Server returned HTTP 405 - SSE not supported")
      throw StreamableHTTPTransportError.sseNotSupported
    default:
      try await throwIfHTTPError(
        response: httpResponse, data: try await consumeByteStream(bytes: bytes))
    }
  }

  /// Sends a request to the server and keeps state to track the pending request.
  private func sendHTTP(request: any JSONRPCRequest) async throws -> HTTPURLResponse {
    // Reset ping timer when sending non-ping requests
    if !(request is PingRequest) {
      resetPingTimer()
    }
    
    pendingRequests[request.id] = request
    do {
      return try await sendHTTP(data: try encoder.encode(request))
    } catch {
      pendingRequests.removeValue(forKey: request.id)
      throw error
    }
  }

  /// Sends a notification to the server.
  private func sendHTTP(notification: any JSONRPCNotification) async throws -> HTTPURLResponse {
    // Reset ping timer when sending notifications
    resetPingTimer()
    return try await sendHTTP(data: try encoder.encode(notification))
  }

  /// Sends a response to the server.
  private func sendHTTP(response: any JSONRPCResponse) async throws -> HTTPURLResponse {
    // Reset ping timer when sending non-ping responses
    if !(response is PingResponse) {
      resetPingTimer()
    }
    return try await sendHTTP(data: try encoder.encode(response))
  }

  /// Sends an error response to the server.
  private func sendHTTP(error: JSONRPCError) async throws -> HTTPURLResponse {
    return try await sendHTTP(data: try encoder.encode(error))
  }

  /// Sends a batch of requests and/or notifications to the server.
  private func sendHTTP(batch: [JSONRPCBatchItem]) async throws -> HTTPURLResponse {
    if batch.isEmpty {
      throw TransportError.emptyBatch
    }

    for item in batch {
      if case .request(let request) = item {
        pendingRequests[request.id] = request
      }
    }
    do {
      let data = try encoder.encode(batch)
      return try await sendHTTP(data: data)
    } catch {
      for item in batch {
        if case .request(let request) = item {
          pendingRequests.removeValue(forKey: request.id)
        }
      }
      throw error
    }
  }

  /// POSTs a message to the server, to either the endpoint returned by the `endpoint` message
  /// sent on the SSE stream (if using the HTTP+SSE transport), or directly to the MCP endpoint
  /// (if using the new Streamable HTTP transport).
  ///
  /// Passes the session ID in the request if a session ID was previously returned by the server
  /// during initialization. If the server rejects the session (with an HTTP 404), this function
  /// automatically re-attempts initialization to acquire a new session ID before retrying sending
  /// the message.
  private func sendHTTP(data: Data) async throws -> HTTPURLResponse {
    var request = URLRequest(url: sendEventEndpointURL ?? serverURL)
    request.httpMethod = "POST"
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    setCommonMCPHeaders(on: &request)
    request.httpBody = data

    let (bytes, response) = try await urlSession.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw StreamableHTTPTransportError.invalidResponse(response)
    }
    switch httpResponse.statusCode {
    case 200:
      // Server is responding to a request -- could either be a JSON
      // response or a new SSE stream. Check the Content-Type to verify.
      let contentType = try getContentType(response: httpResponse)
      switch contentType {
      case "application/json":
        // Check for Keep-Alive headers on JSON responses
        checkForKeepAliveHeaders(in: httpResponse)
        consumerTasks.append(
          Task {
            do {
              try await consumeSingleObjectResponse(stream: bytes)
            } catch {
              logger.error("Error handling application/json response: \(error)")
            }
          })
      case "text/event-stream":
        try await consumeSSEStream(bytes: bytes, waitUntilEndpointEvent: false)
      default:
        throw StreamableHTTPTransportError.invalidContentType(httpResponse, contentType)
      }
    case 202:
      // Server is acknowledging receipt of notification or response
      break
    case 404:
      // MCP servers return 404 to indicate that the session has been
      // terminated. This only applies if the Mcp-Session-Id header was set.
      if request.value(forHTTPHeaderField: "Mcp-Session-Id") != nil {
        // Server has terminated the session; open a new session before retrying the request.
        guard let idGenerator = idGenerator else {
          fatalError(
            "Must call initialize() at least once before attempting to start a new session."
          )
        }
        sessionID = nil
        // Session ID to be set to an updated value after re-initializing
        _ = try await initialize(idGenerator: idGenerator)
        // Retry the original request
        return try await sendHTTP(data: data)
      }
      fallthrough
    default:
      try await throwIfHTTPError(
        response: httpResponse, data: try await consumeByteStream(bytes: bytes))
    }
    return httpResponse
  }

  enum SSEStreamEvent {
    case endpoint(URL)
    case response(TransportResponse, ServerSentEvent)
  }

  /// Throws an error if the response has an errored (4xx or 5xx) status code. Attempts to extract
  /// a JSON-RPC error from the body if it exists.
  private func throwIfHTTPError(response: HTTPURLResponse, data: Data) async throws {
    switch response.statusCode {
    case 200...399:
      // Success
      break
    case 401:
      // Authentication required - attempt to determine resource metadata URL
      var resourceURL: URL?
      let wwwAuthenticate = response.value(forHTTPHeaderField: "WWW-Authenticate")

      if let wwwAuthenticate = wwwAuthenticate {
        // Try to parse resource URL from WWW-Authenticate header
        resourceURL = parseResourceMetadataURL(from: wwwAuthenticate, serverURL: serverURL)
      }

      if resourceURL == nil {
        // Fall back to constructing resource metadata URL from server URL
        // Per older MCP spec (2025-03-26), always attempt metadata discovery on 401
        resourceURL = constructResourceMetadataURL(from: serverURL)
      }

      if let resourceURL = resourceURL {
        throw StreamableHTTPTransportError.authenticationRequired(
          resourceMetadataURL: resourceURL,
          wwwAuthenticate: wwwAuthenticate
        )
      }
      // Fall through to standard error handling if we can't determine resource URL
      fallthrough
    case 400...599:
      // Server may return a JSON-RPC error in the body
      var rpcError: JSONRPCError?
      do {
        rpcError = try decoder.decode(JSONRPCError.self, from: data)
      } catch let error {
        logger.debug(
          "Failed to decode JSONRPCError: \(error). Body: \(String(data: data, encoding: .utf8) ?? "<unknown>")"
        )
      }
      throw StreamableHTTPTransportError.serverHTTPError(response, data, rpcError)
    default:
      // Behavior is undefined
      throw StreamableHTTPTransportError.invalidResponse(response)
    }
  }

  /// Consumes an SSE stream asynchronously. If `waitUntilEndpointEvent` is `true`, this will wait
  /// until the server sends the initial `endpoint` message before asynchronously consuming the
  /// remainder of the stream. If `waitUntilEndpointEvent` is `false`, the entire stream will be
  /// consumed asynchronously and this function will return immediately.
  ///
  /// For finite streams (waitUntilEndpointEvent: false), stream completion is normal and no
  /// reconnection will be attempted.
  private func consumeSSEStream(bytes: URLSession.AsyncBytes, waitUntilEndpointEvent: Bool)
    async throws
  {
    let stream = sseStream(bytes: bytes)
    await incrementSSEConnectionCount()

    // Block until the initial `endpoint` event if requested
    var receivedEndpoint = false
    // When using streamable HTTP, the endpoint event is not required. It's only required
    // when using the legacy SSE transport.
    if !Task.isCancelled
      && !supportsStreamableHTTPTransport
      && waitUntilEndpointEvent
      && sendEventEndpointURL == nil
    {
      guard let event = try await stream.first(where: { _ in true }) else {
        await decrementSSEConnectionCount()
        throw StreamableHTTPTransportError.sseNotSupported
      }
      switch event {
      case let .endpoint(endpointURL):
        receivedEndpoint = true
        sendEventEndpointURL = endpointURL
      case let .response(_, event):
        // We expect to receive an `endpoint` event first -- if something else is
        // is received, this is undefined behavior.
        await decrementSSEConnectionCount()
        throw StreamableHTTPTransportError.sseUnexpectedEvent(event)
      }
    }

    if Task.isCancelled {
      await decrementSSEConnectionCount()
      return
    }

    // Consume the rest of the stream asynchronously
    consumerTasks.append(
      Task {
        do {
          for try await event in stream {
            if Task.isCancelled { break }

            switch event {
            case let .endpoint(endpointURL):
              receivedEndpoint = true
              sendEventEndpointURL = endpointURL
            case let .response(response, sseEvent):
              // When using streamable HTTP, the endpoint event is not required.
              if supportsStreamableHTTPTransport || receivedEndpoint {
                emitResponse(response)
              } else {
                throw StreamableHTTPTransportError.sseUnexpectedEvent(sseEvent)
              }
            }
          }
          await decrementSSEConnectionCount()
        } catch {
          logger.error("Error handling text/event-stream response: \(error)")
          await decrementSSEConnectionCount()
          if Task.isCancelled { return }

          // For finite streams (POST responses), stream completion is normal - don't reconnect
          if !waitUntilEndpointEvent {
            logger.debug("Finite SSE stream ended, this is normal for POST responses")
            return
          }

          // Check if SSE is not supported or has been disabled
          if !sseSupported {
            logger.info("SSE not supported, not attempting reconnection")
            return
          }

          // Check if the error indicates SSE is not supported
          if let transportError = error as? StreamableHTTPTransportError,
            case .sseNotSupported = transportError
          {
            logger.info("SSE not supported, disabling SSE and not attempting reconnection")
            sseSupported = false
            return
          }

          // Attempt to reconnect only for specific network errors and persistent streams
          try await reconnectSSEStream(error: error)
        }
      })
  }

  /// Attempts to reconnect to the SSE stream when disconnected using the `Last-Event-ID` header
  /// for resumability if available. Implements exponential backoff for reconnection attempts.
  private func reconnectSSEStream(error: Error?) async throws {
    // Don't attempt to reconnect if SSE is not supported
    guard sseSupported else {
      logger.info("SSE not supported, skipping reconnection attempt")
      return
    }

    guard reconnectAttempts < Self.maxReconnectAttempts else {
      // Too many reconnection attempts, reset counter but don't retry
      logger.error(
        "Maximum reconnection attempts reached (\(Self.maxReconnectAttempts)). Giving up.")
      reconnectAttempts = 0
      throw StreamableHTTPTransportError.reconnectionFailed
    }

    // Only reconnect for specific network errors
    if let error = error as? URLError {
      let reconnectableErrors: [URLError.Code] = [
        .timedOut,
        .notConnectedToInternet,
        .networkConnectionLost,
      ]

      guard reconnectableErrors.contains(error.code) else {
        logger.info("Not attempting reconnection for error: \(error)")
        return
      }

      logger.info("Attempting reconnection for recoverable error: \(error)")
    } else if error != nil {
      logger.info(
        "Not attempting reconnection for non-network error: \(String(describing: error))")
      return
    }

    // Implement exponential backoff with a reasonable maximum delay
    let backoffFactor = pow(2.0, Double(reconnectAttempts))
    let delayMs = min(Double(reconnectionTimeMs) * backoffFactor, 2 * 60 * 1000.0)  // cap to 2 minutes
    reconnectAttempts += 1

    logger.info(
      "Reconnecting with backoff: attempt \(self.reconnectAttempts)/\(Self.maxReconnectAttempts), delay: \(delayMs)ms"
    )
    try await Task.sleep(for: .milliseconds(delayMs))
    try await openSSEStream()
  }

  /// Creates an event stream from the SSE byte stream by parsing SSE messages in accordance with
  /// the WHATWG specification:
  /// https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream
  private func sseStream(bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<
    SSEStreamEvent, Error
  > {
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let parser = EventSourceParser()
          for try await event in await parser.parse(byteStream: bytes) {
            if Task.isCancelled { break }

            // Keep our reconnection time updated with the parser's
            if let retryMs = event.retryMs {
              reconnectionTimeMs = retryMs
            }
            guard let data = event.data.data(using: .utf8) else {
              logger.error("Received invalid message from server: \(event.data)")
              continue
            }
            // Store the last event ID for resumability if present
            if let id = event.id {
              lastEventID = id
            }

            switch event.eventType {
            case "endpoint":
              continuation.yield(.endpoint(try sendEventURLFromEndpoint(event.data)))
            case "message":
              for response in try decodeAllResponses(
                data: data, requestLookupCache: &pendingRequests, logger: logger, decoder: decoder)
              {
                continuation.yield(.response(response, event))
              }
            default:
              throw StreamableHTTPTransportError.sseInvalidEventType(
                event.eventType)
            }
          }
          continuation.finish()
        } catch let error {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { state in
        if case .cancelled = state {
          task.cancel()
        }
      }
    }
  }

  /// Increments the number of active SSE connections.
  private func incrementSSEConnectionCount() async {
    let previousConnectionCount = activeSSEConnectionCount
    activeSSEConnectionCount += 1
    if previousConnectionCount == 0 {
      Task {
        await connectionStateChannel.send(.connected)
      }
    }
  }

  /// Decrements the number of active SSE connections
  private func decrementSSEConnectionCount() async {
    if activeSSEConnectionCount == 0 {
      fatalError("activeSSEConnectionCount is imbalanced")
    }
    activeSSEConnectionCount -= 1
    if activeSSEConnectionCount == 0 {
      // Don't stop the ping timer here - it should continue running
      // to keep the HTTP connection alive even when SSE is not active
      Task {
        await connectionStateChannel.send(.disconnected)
      }
    }
  }

  /// Consumes an asynchronous byte stream and returns the accumulated data.
  private func consumeByteStream(bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
    }
    return data
  }

  /// Consumes an application/json response from the server that contains a single JSON object.
  /// Parses the object and emits the response.
  private func consumeSingleObjectResponse(stream: URLSession.AsyncBytes) async throws {
    let data = try await consumeByteStream(bytes: stream)
    if Task.isCancelled { return }

    for response in try decodeAllResponses(
      data: data, requestLookupCache: &pendingRequests, logger: logger, decoder: decoder)
    {
      if Task.isCancelled { return }

      emitResponse(response)
    }
  }

  /// Constructs a complete URL to POST JSON-RPC messages to by taking the relative path from the
  /// `endpoint` message sent by the server and appending it to the original server URL.
  private func sendEventURLFromEndpoint(_ endpoint: String) throws -> URL {
    guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
      throw StreamableHTTPTransportError.invalidServerURL(serverURL)
    }
    components.path = ""
    components.query = nil
    components.fragment = nil
    guard let strippedURLStr = components.string else {
      throw StreamableHTTPTransportError.invalidServerURL(serverURL)
    }
    guard let sendEventURL = URL(string: strippedURLStr + endpoint) else {
      throw StreamableHTTPTransportError.sseInvalidEndpoint(endpoint)
    }
    return sendEventURL
  }

  /// Asynchronously emit a response to both response channels.
  private func emitResponse(_ response: TransportResponse) {
    guard let responseChannel = responseChannel,
      let internalResponseChannel = internalResponseChannel
    else {
      fatalError(
        "Cannot send messages before channel is available. Make sure to call start() first")
    }
    Task { await responseChannel.send(response) }
    Task { await internalResponseChannel.send(response) }
  }
  
  /// Starts a timer that sends periodic ping requests to keep the connection alive.
  private func startPingTimer() {
    guard let interval = pingInterval else { 
      return 
    }
    
    stopPingTimer()
    
    pingTask = Task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(interval))
          
          if !Task.isCancelled {
            await self.sendPing()
          }
        } catch {
          break
        }
      }
    }
  }
  
  /// Stops the ping timer.
  private func stopPingTimer() {
    pingTask?.cancel()
    pingTask = nil
  }
  
  /// Resets the ping timer by restarting it. This is called when a request is sent
  /// to ensure we only send pings during idle periods.
  private func resetPingTimer() {
    if pingInterval != nil {
      startPingTimer()
    }
  }
  
  /// Sends a ping request to the server.
  private func sendPing() async {
    guard let idGenerator = idGenerator else { 
      return 
    }
    
    let pingRequest = PingRequest(id: idGenerator())
    do {
      try await send(request: pingRequest)
    } catch {
      logger.error("Failed to send ping request: \(error)")
    }
  }
  
  /// Checks for Keep-Alive headers in an HTTP response and configures ping timer if found.
  private func checkForKeepAliveHeaders(in httpResponse: HTTPURLResponse) {
    if let connectionHeader = httpResponse.value(forHTTPHeaderField: "Connection"),
       connectionHeader.lowercased().contains("keep-alive"),
       let keepAliveHeader = httpResponse.value(forHTTPHeaderField: "Keep-Alive") {
      
      // Parse the Keep-Alive header for timeout parameter
      if let timeout = parseKeepAliveTimeout(from: keepAliveHeader) {
        // Set ping interval to be shorter than the timeout to avoid hitting it
        // Use 80% of the timeout value, with a minimum of 1 second
        let newPingInterval = max(1.0, timeout * 0.8)
        pingInterval = newPingInterval
      }
    }
  }
}

/// Validates a session ID (sent by the server in the `Mcp-Session-Id` HTTP header) by ensuring
/// that it is non-empty and only contains characters in the visible ASCII range. Returns the
/// session ID unmodified upon success, or throws `StreamableHTTPTransportError.invalidSessionID`.
private func validateSessionID(_ input: String) throws -> String {
  if input.isEmpty {
    throw StreamableHTTPTransportError.invalidSessionID(input)
  }
  let visibleASCIIRange = 0x21...0x7E
  for unicodeScalar in input.unicodeScalars {
    let value = Int(unicodeScalar.value)
    if !visibleASCIIRange.contains(value) {
      throw StreamableHTTPTransportError.invalidSessionID(input)
    }
  }
  return input
}

/// Parses the `Content-Type` header from an HTTP response and strips out attributes to return just
/// the content type.
private func getContentType(response: HTTPURLResponse) throws -> String {
  guard let headerValue = response.value(forHTTPHeaderField: "Content-Type"), !headerValue.isEmpty
  else {
    throw StreamableHTTPTransportError.missingContentType(response)
  }
  let parts = headerValue.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
  guard let contentType = parts.first?.trimmingCharacters(in: .whitespaces) else {
    throw StreamableHTTPTransportError.invalidContentType(response, headerValue)
  }
  return contentType
}

// Cached regex for parsing WWW-Authenticate header
private nonisolated(unsafe) let resourceParameterRegex = /resource\s*=\s*"([^"]+)"/

/// Constructs a resource metadata URL from the server URL.
/// This is used as a fallback when the WWW-Authenticate header is not present.
private func constructResourceMetadataURL(from serverURL: URL) -> URL? {
  // Get the base URL (scheme + host + port if present)
  guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
    return nil
  }

  // Reset path, query and fragment to get just the base URL
  components.path = ""
  components.query = nil
  components.fragment = nil

  guard let baseURL = components.url else {
    return nil
  }

  // Construct the well-known MCP resource metadata URL
  return baseURL.appendingPathComponent(".well-known/mcp-resource")
}

/// Parses the resource metadata URL from the WWW-Authenticate header.
/// According to the MCP specification, the header provides the location of resource metadata.
private func parseResourceMetadataURL(from wwwAuthenticate: String, serverURL: URL) -> URL? {
  // The WWW-Authenticate header for MCP should indicate where to find resource metadata
  // Format: Bearer realm="<url>", resource="<metadata-url>"
  // We need to extract the resource metadata URL from this header

  // First, check if it's a Bearer authentication scheme
  guard wwwAuthenticate.lowercased().hasPrefix("bearer") else {
    return nil
  }

  // Extract the resource parameter value using Swift Regex
  if let match = try? resourceParameterRegex.firstMatch(in: wwwAuthenticate) {
    let resourceURLString = String(match.1)

    // If it's already an absolute URL, use it directly
    if let url = URL(string: resourceURLString), url.scheme != nil {
      return url
    }

    // Otherwise, resolve it relative to the server URL
    return URL(string: resourceURLString, relativeTo: serverURL)
  } else {
    // If no resource parameter, construct default well-known URL
    var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
    components?.path = "/.well-known/oauth-protected-resource"
    components?.query = nil
    components?.fragment = nil
    return components?.url
  }
}

/// Errors thrown by `StreamableHTTPTransport`
public enum StreamableHTTPTransportError: Error, LocalizedError {
  /// Thrown when the `severURL` used to initialize the transport is invalid.
  case invalidServerURL(URL)

  /// Thrown when an unexpected response is received for an HTTP request.
  case invalidResponse(URLResponse)

  /// Thrown when the response is missing a Content-Type header.
  case missingContentType(HTTPURLResponse)

  /// Thrown when the Content-Type of a response is not a supported type.
  case invalidContentType(HTTPURLResponse, String)

  /// Thrown when the server returns an error. The associated values are
  /// the HTTP response, the data returned in the response body, and the
  /// `JSONRPCError` if an error could be decoded from the response body.
  case serverHTTPError(HTTPURLResponse, Data, JSONRPCError?)

  /// Thrown when an SSE event with an invalid event type is received.
  case sseInvalidEventType(String)

  /// Thrown when an `endpoint` SSE event is received with an invalid URI.
  case sseInvalidEndpoint(String)

  /// Thrown when the server returns a response code (HTTP 405) indicating
  /// that it does not offer an SSE stream.
  case sseNotSupported

  /// Thrown when an `endpoint` SSE event was expected, but a different event
  /// was sent first.
  case sseUnexpectedEvent(ServerSentEvent)

  /// Thrown when the server sends an invalid value in the `Mcp-Session-Id`
  /// HTTP header. Only the visible range of ASCII characters is supported.
  case invalidSessionID(String)

  /// Thrown when the maximum number of reconnection attempts has been reached.
  case reconnectionFailed

  /// Thrown when the server requires authentication (HTTP 401).
  /// The associated values are the resource metadata URL and optional WWW-Authenticate header value.
  case authenticationRequired(resourceMetadataURL: URL, wwwAuthenticate: String?)

  public var errorDescription: String? {
    switch self {
    case .invalidServerURL(let URL):
      return "Invalid server URL: \(URL)"
    case .invalidResponse(let response):
      return "Invalid HTTP response: \(response)"
    case .missingContentType(let response):
      return "HTTP response missing Content-Type header (status code: \(response.statusCode))"
    case .invalidContentType(let response, let contentType):
      return
        "HTTP response has unsupported Content-Type: \(contentType) (status code: \(response.statusCode))"
    case .serverHTTPError(let response, _, let rpcError):
      if let rpcError = rpcError {
        return
          "Server HTTP error (status code: \(response.statusCode)): \(rpcError.error.message)"
      } else {
        return "Server HTTP error (status code: \(response.statusCode))"
      }
    case .sseInvalidEventType(let eventType):
      return "Server sent event with invalid event type: \(eventType)"
    case .sseInvalidEndpoint(let uri):
      return "Server sent invalid endpoint URI: \(uri)"
    case .sseNotSupported:
      return "Server does not support Server-Sent Events (SSE)"
    case .sseUnexpectedEvent(let event):
      return
        "Unexpected server-sent event type '\(event.eventType)' when 'endpoint' was expected"
    case .invalidSessionID(let sessionID):
      return "Server sent invalid session ID: \(sessionID)"
    case .reconnectionFailed:
      return "Failed to reconnect to server after maximum number of attempts"
    case .authenticationRequired:
      return "Server requires authentication"
    }
  }

  public var failureReason: String? {
    switch self {
    case .invalidServerURL:
      return "The server URL was not valid"
    case .invalidResponse:
      return "The server response was not a valid HTTP response"
    case .missingContentType:
      return "The Content-Type header is required but was missing"
    case .invalidContentType(_, let contentType):
      return "Content-Type '\(contentType)' is not supported for this request"
    case .serverHTTPError(let response, _, _):
      return "Server returned HTTP error status code \(response.statusCode)"
    case .sseInvalidEventType:
      return "Only 'endpoint' and 'message' event types are supported"
    case .sseInvalidEndpoint:
      return "The endpoint URI could not be parsed"
    case .sseNotSupported:
      return "The server returned HTTP 405 Method Not Allowed"
    case .sseUnexpectedEvent:
      return "The initial event in an SSE stream must be of type 'endpoint'"
    case .invalidSessionID:
      return "Session ID must contain only visible ASCII characters (0x21-0x7E)"
    case .reconnectionFailed:
      return "Too many reconnection attempts after connection loss"
    case .authenticationRequired:
      return "The server returned HTTP 401 Unauthorized with authentication metadata"
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .invalidServerURL:
      return "Check that the server URL has a valid format"
    case .invalidResponse:
      return "Check server compatibility with MCP streamable HTTP transport"
    case .missingContentType:
      return "Ensure the server includes Content-Type header in responses"
    case .invalidContentType:
      return
        "Ensure the server returns 'application/json' or 'text/event-stream' Content-Type"
    case .serverHTTPError(_, _, let rpcError):
      if let rpcError = rpcError {
        return "Review the JSON-RPC error details: \(rpcError.error.message)"
      } else {
        return "Check server logs for more information about the error"
      }
    case .sseInvalidEventType:
      return "Verify server SSE implementation follows MCP protocol specification"
    case .sseInvalidEndpoint:
      return "Ensure the server sends a valid URL in the 'endpoint' event"
    case .sseNotSupported:
      return "Verify the server supports MCP streamable HTTP transport"
    case .sseUnexpectedEvent:
      return "Verify server SSE implementation sends 'endpoint' event first"
    case .invalidSessionID:
      return "Ensure server generates valid session IDs"
    case .reconnectionFailed:
      return "Check network connectivity and server availability"
    case .authenticationRequired:
      return "Authenticate with the server using OAuth 2.0 to obtain an access token"
    }
  }
}

/// Parses the Keep-Alive header to extract the timeout parameter value.
/// The Keep-Alive header format is: `Keep-Alive: timeout=<seconds>, max=<requests>`
/// This function extracts the timeout value in seconds.
private func parseKeepAliveTimeout(from keepAliveHeader: String) -> TimeInterval? {
  let parameters = keepAliveHeader.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  
  for parameter in parameters {
    if parameter.lowercased().hasPrefix("timeout=") {
      let value = parameter.dropFirst("timeout=".count)
      if let timeoutSeconds = Int(value) {
        return TimeInterval(timeoutSeconds)
      }
    }
  }
  
  return nil
}
