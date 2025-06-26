// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

// https://www.jsonrpc.org/specification
public let JSONRPCVersion = "2.0"

public enum JSONRPCReservedError: Int, Error, LocalizedError, Equatable {
  case parseError = -32700
  case invalidRequest = -32600
  case methodNotFound = -32601
  case invalidParams = -32602
  case internalError = -32603

  public var errorDescription: String? {
    switch self {
    case .parseError:
      return "Parse error"
    case .invalidRequest:
      return "Invalid Request"
    case .methodNotFound:
      return "Method not found"
    case .invalidParams:
      return "Invalid params"
    case .internalError:
      return "Internal error"
    }
  }
}

public enum JSONRPCParams: Codable, Equatable, ExpressibleByArrayLiteral,
  ExpressibleByDictionaryLiteral
{
  case byPosition([JSONValue])
  case byName([String: JSONValue])

  // MARK: Decodable

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let arrayValue = try? container.decode([JSONValue].self) {
      self = .byPosition(arrayValue)
    } else if let objectValue = try? container.decode([String: JSONValue].self) {
      self = .byName(objectValue)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected either an array or an object"
      )
    }
  }

  // MARK: Encodable

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .byPosition(let array):
      try container.encode(array)
    case .byName(let object):
      try container.encode(object)
    }
  }

  // MARK: ExpressibleByArrayLiteral

  public init(arrayLiteral elements: any JSONRepresentable...) {
    self = .byPosition(elements.map { $0.jsonValue })
  }

  // MARK: ExpressibleByDictionaryLiteral

  public init(dictionaryLiteral elements: (String, any JSONRepresentable)...) {
    self = .byName(
      [String: JSONValue](
        elements.map { ($0, $1.jsonValue) },
        uniquingKeysWith: { (first, _) in first }
      ))
  }
}

public enum JSONRPCRequestID: Codable, Equatable, Hashable, Sendable, ExpressibleByStringLiteral,
  ExpressibleByIntegerLiteral, CustomStringConvertible
{
  case string(String)
  case number(Int)

  // MARK: Decodable

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let stringValue = try? container.decode(String.self) {
      self = .string(stringValue)
    } else if let intValue = try? container.decode(Int.self) {
      self = .number(intValue)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected either a string or an integer"
      )
    }
  }

  // MARK: Encodable

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .string(let stringValue):
      try container.encode(stringValue)
    case .number(let intValue):
      try container.encode(intValue)
    }
  }

  // MARK: ExpressibleByStringLiteral

  public init(stringLiteral value: StringLiteralType) {
    self = .string(value)
  }

  // MARK: ExpressibleByIntegerLiteral

  public init(integerLiteral value: IntegerLiteralType) {
    self = .number(value)
  }

  // MARK: CustomStringConvertible

  public var description: String {
    switch self {
    case let .string(stringValue):
      return stringValue
    case let .number(intValue):
      return String(intValue)
    }
  }
}

public protocol JSONRPCRequest: Codable, Sendable {
  associatedtype Response: JSONRPCResponse
  associatedtype Params: Codable
  typealias ResponseDecoder = @Sendable (JSONDecoder, Data) throws -> Response

  var jsonrpc: String { get }
  var method: String { get }
  var params: Params { get }
  var id: JSONRPCRequestID { get }
  var responseDecoder: ResponseDecoder { get }
}

public protocol JSONRPCNotification: Codable, Sendable {
  associatedtype Params: Codable

  var jsonrpc: String { get }
  var method: String { get }
  var params: Params { get }
}

public protocol JSONRPCResponse: Codable, Sendable {
  associatedtype Result: Codable

  var jsonrpc: String { get }
  var result: Result { get }
  var id: JSONRPCRequestID { get }
}

public struct JSONRPCError: Codable, Sendable {
  public struct ErrorBody: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: JSONValue?
  }

  public let jsonrpc: String
  public let error: ErrorBody
  public let id: JSONRPCRequestID?

  public init(error: ErrorBody, id: JSONRPCRequestID?) {
    self.jsonrpc = JSONRPCVersion
    self.error = error
    self.id = id
  }

  public init(reservedError: JSONRPCReservedError, id: JSONRPCRequestID?) {
    self.jsonrpc = JSONRPCVersion
    self.error = ErrorBody(
      code: reservedError.rawValue, message: reservedError.localizedDescription, data: nil)
    self.id = id
  }
}

/// Represents a JSON-RPC batch request item which can be either a request or notification.
public enum JSONRPCBatchItem: Encodable, Sendable {
  case request(any JSONRPCRequest)
  case notification(any JSONRPCNotification)

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .request(let request):
      try request.encode(to: encoder)
    case .notification(let notification):
      try notification.encode(to: encoder)
    }
  }
}

/// Represents a JSON-RPC batch response item which can be either a success response or error.
public enum JSONRPCBatchResponseItem: Codable, Sendable {
  case success(any JSONRPCResponse)
  case error(JSONRPCError)

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .success(let response):
      try response.encode(to: encoder)
    case .error(let error):
      try error.encode(to: encoder)
    }
  }

  public init(from decoder: Decoder) throws {
    // This is a placeholder. The actual decoding will happen in Transport implementations
    // since we need to know the concrete types to properly decode.
    throw DecodingError.dataCorruptedError(
      in: try decoder.singleValueContainer(),
      debugDescription:
        "JSONRPCBatchResponseItem cannot be decoded generically; use specific decoders"
    )
  }
}
