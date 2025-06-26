// Copyright © 2025 Indragie Karunaratne. All rights reserved.

/// A macro that generates conformance to the `JSONRPCRequest` protocol.
///
/// This macro generates the required properties and initialization method
/// for a type to conform to the `JSONRPCRequest` protocol. This macro can
/// only be applied to a struct, and the struct must contain a nested
/// definition for a struct named `Params` that contains the parameters
/// to include in the request.
///
/// - Parameters:
///   - method: The JSON-RPC method name for this request.
///   - responseType: The type that will be used to decode the response.
///
/// Example usage:
/// ```swift
/// @JSONRPCRequest(method: "initialize", responseType: InitializeResponse.self)
/// struct InitializeRequest {
///     struct Params: Codable {
///         let protocolVersion: String
///         let capabilities: ClientCapabilities
///         let clientInfo: Implementation
///     }
/// }
/// ```
@attached(
  extension,
  conformances: JSONRPCRequest,
  Codable,
  CustomDebugStringConvertible,
  CustomStringConvertible
)
@attached(
  member,
  names: named(jsonrpc),
  named(method),
  named(params),
  named(id),
  named(responseDecoder),
  named(init),
  named(CodingKeys),
  named(Response),
  named(debugDescription),
  named(description)
)
public macro JSONRPCRequest<T: JSONRPCResponse>(method: String, responseType: T.Type) =
  #externalMacro(module: "ContextCoreMacros", type: "JSONRPCRequestMacro")

/// A macro that generates conformance to the `JSONRPCNotification` protocol.
///
/// This macro generates the required properties and initialization method
/// for a type to conform to the `JSONRPCNotification` protocol. This macro can
/// only be applied to a struct, and the struct must contain a nested
/// definition for a struct named `Params` that contains the parameters
/// to include in the request.
///
/// - Parameters:
///   - method: The JSON-RPC method name for this notification.
///
/// Example usage:
/// ```swift
/// @JSONRPCNotification(method: "initialized")
/// struct InitializedNotification {
///     struct Params: Codable {}
/// }
/// ```
@attached(
  extension,
  conformances: JSONRPCNotification,
  Codable,
  CustomDebugStringConvertible,
  CustomStringConvertible
)
@attached(
  member,
  names: named(jsonrpc),
  named(method),
  named(params),
  named(init),
  named(CodingKeys),
  named(debugDescription),
  named(description)
)
public macro JSONRPCNotification(method: String) =
  #externalMacro(module: "ContextCoreMacros", type: "JSONRPCNotificationMacro")

/// A macro that generates conformance to the `JSONRPCResponse` protocol.
///
/// This macro generates the required properties and initialization method
/// for a type to conform to the `JSONRPCResponse` protocol. This macro can
/// only be applied to a struct, and the struct must contain a nested
/// definition for a struct named `Result` that contains the members included
/// in the result contained within the response.
///
/// Example usage:
/// ```swift
/// @JSONRPCResponse
/// struct InitializeResponse {
///     struct Result: Codable {
///         let protocolVersion: String
///         let capabilities: ServerCapabilities
///         let serverInfo: Implementation
///     }
/// }
/// ```
@attached(
  extension,
  conformances: JSONRPCResponse,
  Codable,
  CustomDebugStringConvertible,
  CustomStringConvertible
)
@attached(
  member,
  names: named(jsonrpc),
  named(result),
  named(id),
  named(init),
  named(CodingKeys),
  named(debugDescription),
  named(description)
)
public macro JSONRPCResponse() =
  #externalMacro(module: "ContextCoreMacros", type: "JSONRPCResponseMacro")
