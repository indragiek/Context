// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// A response from the server, which can be a successful response to a request,
/// an error response to a request, a server-initiated notification, a server-initiated request, or a server error.
public enum TransportResponse: Sendable {
  case successfulRequest(request: any JSONRPCRequest, response: any JSONRPCResponse, data: Data)
  case failedRequest(request: any JSONRPCRequest, error: JSONRPCError, data: Data)
  case decodingError(request: (any JSONRPCRequest)?, error: DecodingError, data: Data)
  case serverNotification(any JSONRPCNotification, data: Data)
  case serverRequest(any JSONRPCRequest, data: Data)
  case serverError(JSONRPCError, data: Data)
}

/// Errors thrown by `Transport` implementations.
public enum TransportError: Error {
  /// Thrown when the client receives a response for a request that it did not
  /// originally send.
  case requestNotFound(JSONRPCRequestID, data: Data)

  /// Thrown when the client does not receive a response to a request that it sent.
  case noResponse

  /// Thrown when the response was of a type that was not expected.
  case unexpectedResponse(request: any JSONRPCRequest, response: any JSONRPCResponse, data: Data)

  /// Thrown when a notification with an unknown method is received.
  case unexpectedNotification(method: String, data: Data)

  /// Thrown when a request with an unknown method is received from the server.
  case unexpectedRequest(method: String, data: Data)

  /// Thrown when the received message is not a valid JSON-RPC message.
  case invalidMessage(data: Data)

  /// Thrown when the server returns a failure response to initialization.
  case initializationFailed(request: InitializeRequest, error: JSONRPCError, data: Data)

  /// Thrown when a request times out waiting for a response.
  case timeout

  /// Thrown when attempting to use the transport before calling start().
  case notStarted
}

extension TransportError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .requestNotFound(id, data: data):
      let json = String(data: data, encoding: .utf8) ?? "<data: \(data.count) bytes>"
      return "Received a response for a request with ID '\(id)', which the client did not send. \(json)"
    case .noResponse:
      return "No response received from server"
    case let .unexpectedResponse(request, response, data):
      // Create JSON payload with both request and response
      var payload: [String: JSONValue] = [:]
      
      // Encode the request
      if let requestData = try? JSONEncoder().encode(request),
         let requestJSON = try? JSONDecoder().decode(JSONValue.self, from: requestData) {
        payload["request"] = requestJSON
      }
      
      // Decode the response data
      if let responseJSON = try? JSONDecoder().decode(JSONValue.self, from: data) {
        payload["response"] = responseJSON
      }
      
      let jsonPayload = JSONValue.object(payload)
      let json = JSONUtility.compactString(from: jsonPayload) ?? String(data: data, encoding: .utf8) ?? "<data: \(data.count) bytes>"
      return "Unexpected response type: \(type(of: response)). \(json)"
    case let .unexpectedNotification(method, data):
      let json = String(data: data, encoding: .utf8) ?? "<data: \(data.count) bytes>"
      return "Unexpected notification with method \"\(method)\". \(json)"
    case let .unexpectedRequest(method, data):
      let json = String(data: data, encoding: .utf8) ?? "<data: \(data.count) bytes>"
      return "Unexpected request with method \"\(method)\". \(json)"
    case let .invalidMessage(data):
      let json =
        String(data: data, encoding: .utf8) ?? "<data: \(data.count) bytes>"
      return "JSON-RPC message could not be parsed. \(json)"
    case let .initializationFailed(request, error, data):
      // Create JSON payload with both request and response
      var payload: [String: JSONValue] = [:]
      
      // Encode the request
      if let requestData = try? JSONEncoder().encode(request),
         let requestJSON = try? JSONDecoder().decode(JSONValue.self, from: requestData) {
        payload["request"] = requestJSON
      }
      
      // Decode the response data
      if let responseJSON = try? JSONDecoder().decode(JSONValue.self, from: data) {
        payload["response"] = responseJSON
      }
      
      let jsonPayload = JSONValue.object(payload)
      let json = JSONUtility.compactString(from: jsonPayload) ?? String(data: data, encoding: .utf8) ?? "<data: \(data.count) bytes>"
      return "Initialization failed (code: \(error.error.code), message: \"\(error.error.message)\"). \(json)"
    case .timeout:
      return "Request timed out"
    case .notStarted:
      return "Transport is not started. Make sure to call start() first"
    }
  }
}

/// Indicates whether the transport is connected to the server.
public enum TransportConnectionState: Sendable {
  case connected
  case disconnected
}

/// A transport mechanism for client-server communications.
public protocol Transport: Actor {
  associatedtype ResponseSequence: AsyncSequence, Sendable
  where ResponseSequence.Element == TransportResponse, ResponseSequence.Failure == Error
  associatedtype LogSequence: AsyncSequence, Sendable
  where LogSequence.Element == String, LogSequence.Failure == Error
  associatedtype ConnectionStateSequence: AsyncSequence, Sendable
  where
    ConnectionStateSequence.Element == TransportConnectionState,
    ConnectionStateSequence.Failure == Error

  /// Generates a new request ID.
  typealias IDGenerator = @Sendable () -> JSONRPCRequestID

  /// Start communicating with the server. Must be called before calling
  /// any other method.
  func start() async throws

  /// Sends an initialization request to the server. Upon successful initialization,
  /// sends an initialized notification to confirm initialization. Otherwise,
  /// throws an error.
  ///
  /// - Parameter idGenerator: Used to generate an ID for the initialization request.
  /// - Returns: The server's response to initialization if successful, which contains
  /// the latest protocol version supported by the server, the server's capabilities,
  /// and the server name & version.
  func initialize(idGenerator: @escaping IDGenerator) async throws -> InitializeResponse.Result

  /// Send a request to the server.
  /// - Parameter request: The request to send to the server.
  func send(request: any JSONRPCRequest) async throws

  /// Send a notification to the server. No response will be returned.
  /// - Parameter notification: The notification to send to the server.
  func send(notification: any JSONRPCNotification) async throws

  /// Send a response to the server in response to a request sent by the server.
  /// - Parameter response: The response to send to the server.
  func send(response: any JSONRPCResponse) async throws

  /// Send an error response to the server in response to a request sent by the server.
  /// - Parameter error: The error response to send to the server.
  func send(error: JSONRPCError) async throws

  /// Receive a stream of responses from the server.
  /// - Returns: An async sequence of responses received from the server.
  func receive() async throws -> ResponseSequence

  /// Receive a stream of logs from the server. The server should typically send logs via
  /// notifications as described in:
  /// https://modelcontextprotocol.io/specification/2025-03-26/server/utilities/logging
  ///
  /// However, this exists for transports that want to send logs out of band -- for example,
  /// the `StdioTransport` supports logging over stderr, and this function is implemented
  /// to capture those logs.
  func receiveLogs() async throws -> LogSequence

  /// Receive a stream of connection state updates from the server.
  func receiveConnectionState() async throws -> ConnectionStateSequence

  /// Close the connection to the server. Subsequent calls to `start`, `send`
  /// or `receive` will throw an error.
  func close() async throws
}

extension Transport {
  /// Send a request and wait for the response to be sent by the server.
  /// - Parameter request: The request to send to the server.
  /// - Returns: The server's response to the request.
  /// - Throws: `TransportError.noResponse` if no response was sent by the server for
  /// the specified request.
  func testOnly_sendAndWaitForResponse(request: any JSONRPCRequest) async throws
    -> TransportResponse
  {
    try await send(request: request)
    return try await testOnly_waitForResponse(id: request.id)
  }

  /// Waits for the server to send a response to a specified request ID.
  /// - Parameter id: The ID of the request to wait for a response for.
  /// - Returns: The server's response to the request with the specified ID.
  /// - Throws: `TransportError.noResponse` if no response was sent by the server for
  /// the specified ID.
  func testOnly_waitForResponse(id: JSONRPCRequestID) async throws -> TransportResponse {
    for try await response in try await receive() {
      switch response {
      case .successfulRequest(request: let r, response: _, data: _):
        if r.id == id {
          return response
        }
      case .failedRequest(request: let r, error: _, data: _):
        if r.id == id {
          return response
        }
      case .decodingError(request: let r, error: _, data: _):
        if r?.id == id {
          return response
        }
      case .serverNotification(_, _), .serverRequest(_, _), .serverError(_, _):
        // Skip notifications, server requests, and errors as they are not responses to our request
        continue
      }
    }
    throw TransportError.noResponse
  }
}

// Simplified JSON structure to determine the type of message
private struct JSONRPCMessageType: Codable {
  let jsonrpc: String?
  let method: String?
  let id: JSONRPCRequestID?
  let error: JSONRPCError.ErrorBody?
}

// Registry of notification types that can be decoded
private enum NotificationRegistry {
  private static let types: [String: any JSONRPCNotification.Type] = [
    "notifications/initialized": InitializedNotification.self,
    "notifications/cancelled": CancelledNotification.self,
    "notifications/progress": ProgressNotification.self,
    "notifications/message": LoggingMessageNotification.self,
    "notifications/stderr": StderrNotification.self,
    "notifications/resources/list_changed": ResourceListChangedNotification.self,
    "notifications/resources/updated": ResourceUpdatedNotification.self,
    "notifications/prompts/list_changed": PromptListChangedNotification.self,
    "notifications/tools/list_changed": ToolListChangedNotification.self,
  ]

  static func notificationType(for method: String) -> (any JSONRPCNotification.Type)? {
    return types[method]
  }
}

// Registry of request types that can be decoded (for server-initiated requests)
private enum RequestRegistry {
  private static let types: [String: any JSONRPCRequest.Type] = [
    "sampling/createMessage": CreateMessageRequest.self,
    "ping": PingRequest.self,
    "roots/list": ListRootsRequest.self
  ]

  static func requestType(for method: String) -> (any JSONRPCRequest.Type)? {
    return types[method]
  }
}

/// Decodes responses returned by the server. The request
/// lookup cache is used to look up the original request object matching the request ID, which is
/// required to decode the response.
func decodeAllResponses(
  data: Data, requestLookupCache: inout [JSONRPCRequestID: any JSONRPCRequest],
  logger: Logger? = nil,
  decoder: JSONDecoder = JSONDecoder()
) throws -> [TransportResponse] {
  let response = try decodeSingleResponse(
    data: data,
    requestLookupCache: &requestLookupCache,
    decoder: decoder
  )
  logResponse(response, logger: logger)
  return [
    response
  ]
}

/// Decodes a single response returned by the server. The request lookup cache is used to look up
/// the original request object matching the request ID, which is required to decode the response.
func decodeSingleResponse(
  data: Data, requestLookupCache: inout [JSONRPCRequestID: any JSONRPCRequest],
  logger: Logger? = nil,
  decoder: JSONDecoder = JSONDecoder()
) throws -> TransportResponse {
  do {
    // First try to determine the type of message
    let messageType = try decoder.decode(JSONRPCMessageType.self, from: data)
    do {
      // If there's a method but no ID, it's a notification
      if let method = messageType.method, messageType.id == nil {
        guard let notificationType = NotificationRegistry.notificationType(for: method) else {
          throw TransportError.unexpectedNotification(method: method, data: data)
        }

        let notification = try decoder.decode(notificationType, from: data)
        return .serverNotification(notification, data: data)
      }

      // Check for error message without an ID (server error)
      if messageType.error != nil && messageType.id == nil {
        let error = try decoder.decode(JSONRPCError.self, from: data)
        return .serverError(error, data: data)
      }

      // If there's a method and an ID, check if it's a server request or a response to our request
      if let method = messageType.method, let id = messageType.id {
        // Check if this is a response to a request we sent
        if let request = requestLookupCache[id] {
          // This is a response to our request
          if messageType.error != nil {
            let error = try decoder.decode(JSONRPCError.self, from: data)
            requestLookupCache.removeValue(forKey: request.id)
            return .failedRequest(request: request, error: error, data: data)
          } else {
            let response = try request.responseDecoder(decoder, data)
            requestLookupCache.removeValue(forKey: request.id)
            return .successfulRequest(request: request, response: response, data: data)
          }
        } else {
          // This is a server request - method and ID but not in our cache
          guard let requestType = RequestRegistry.requestType(for: method) else {
            throw TransportError.unexpectedRequest(method: method, data: data)
          }
          let request = try decoder.decode(requestType, from: data)
          return .serverRequest(request, data: data)
        }
      }

      // It's a response (success or error) with an ID but no method
      if let id = messageType.id {
        // If error field exists, it's an error response
        if messageType.error != nil {
          let error = try decoder.decode(JSONRPCError.self, from: data)

          guard let request = requestLookupCache[id] else {
            throw TransportError.requestNotFound(id, data: data)
          }
          requestLookupCache.removeValue(forKey: request.id)
          return .failedRequest(request: request, error: error, data: data)
        }

        // Otherwise it's a success response
        guard let request = requestLookupCache[id] else {
          throw TransportError.requestNotFound(id, data: data)
        }
        let response = try request.responseDecoder(decoder, data)
        requestLookupCache.removeValue(forKey: request.id)
        return .successfulRequest(request: request, response: response, data: data)
      }

      // Not a valid message
      throw TransportError.invalidMessage(data: data)
    } catch let decodingError as DecodingError {
      var request: (any JSONRPCRequest)?
      if let id = messageType.id {
        request = requestLookupCache[id]
      }
      return .decodingError(request: request, error: decodingError, data: data)
    }
  } catch let transportError as TransportError {
    // Re-throw TransportError types without wrapping them
    throw transportError
  } catch {
    throw TransportError.invalidMessage(data: data)
  }
}

/// Logs the specified response for debugging purposes.
private func logResponse(_ response: TransportResponse, logger: Logger?) {
  guard let logger = logger else {
    return
  }
  switch response {
  case let .successfulRequest(request: request, response: response, data: _):
    logger.trace(
      "[successfulRequest] request: \(String(reflecting: request), privacy: .private), response: \(String(reflecting: response), privacy: .private)"
    )
  case let .failedRequest(request: request, error: error, data: _):
    logger.trace(
      "[failedRequest] request: \(String(reflecting: request), privacy: .private), error: \(String(reflecting: error), privacy: .private)"
    )
  case let .serverNotification(notification, data: _):
    logger.trace(
      "[serverNotification] request: \(String(reflecting: notification), privacy: .private)")
  case let .serverRequest(request, data: _):
    logger.trace("[serverRequest] request: \(String(reflecting: request), privacy: .private)")
  case let .serverError(error, data: _):
    logger.trace("[serverError] \(String(reflecting: error), privacy: .private)")
  case let .decodingError(request, error, data):
    let str = String(data: data, encoding: .utf8) ?? "<invalid>"
    logger.trace(
      "[decodingError] request: \(String(reflecting: request), privacy: .private), error: \(String(reflecting: error), privacy: .private), data: \(str, privacy: .private)"
    )
  }
}
