// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// A type that can be encoded in JSON
public protocol JSONRepresentable {
  var jsonValue: JSONValue { get }
}

/// Errors emitted by `JSONValue`
public enum JSONValueError: Error, LocalizedError, Equatable {
  case invalidUTF8Data(Data)
  case invalidUTF8String(String)

  public var errorDescription: String? {
    switch self {
    case let .invalidUTF8Data(data):
      return "Data is invalid UTF-8: \(data)"
    case let .invalidUTF8String(string):
      return "String is invalid UTF-8: \(string)"
    }
  }
}

/// A Codable-conforming container that can store arbitrary JSON values with mixed types.
public enum JSONValue: Sendable {
  case null
  case number(Double)
  case integer(Int64)
  case boolean(Bool)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(decoding jsonData: Data, decoder: JSONDecoder = JSONDecoder()) throws {
    self = try decoder.decode(JSONValue.self, from: jsonData)
  }

  public init(decoding jsonString: String, decoder: JSONDecoder = JSONDecoder()) throws {
    guard let data = jsonString.data(using: .utf8) else {
      throw JSONValueError.invalidUTF8String(jsonString)
    }
    try self.init(decoding: data, decoder: decoder)
  }

  public func encodeData(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
    return try encoder.encode(self)
  }

  public func encodeString(encoder: JSONEncoder = JSONEncoder()) throws -> String {
    let data = try encodeData(encoder: encoder)
    guard let jsonString = String(data: data, encoding: .utf8) else {
      throw JSONValueError.invalidUTF8Data(data)
    }
    return jsonString
  }
}

extension JSONValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Unsupported value type cannot be decoded")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .number(let number):
      try container.encode(number)
    case .integer(let integer):
      try container.encode(integer)
    case .boolean(let boolean):
      try container.encode(boolean)
    case .string(let string):
      try container.encode(string)
    case .array(let array):
      try container.encode(array)
    case .object(let object):
      try container.encode(object)
    }
  }
}

extension JSONValue: JSONRepresentable {
  public var jsonValue: JSONValue { return self }
}

extension JSONValue: Equatable {
  public static func == (lhsValue: JSONValue, rhsValue: JSONValue) -> Bool {
    switch (lhsValue, rhsValue) {
    case (.null, .null):
      return true
    case let (.number(lhs), .number(rhs)):
      return lhs == rhs
    case let (.integer(lhs), .integer(rhs)):
      return lhs == rhs
    case let (.boolean(lhs), .boolean(rhs)):
      return lhs == rhs
    case let (.string(lhs), .string(rhs)):
      return lhs == rhs
    case let (.array(lhs), .array(rhs)):
      return lhs == rhs
    case let (.object(lhs), .object(rhs)):
      return lhs == rhs
    default:
      return false
    }
  }
}

extension JSONValue: Hashable {
  public func hash(into hasher: inout Hasher) {
    switch self {
    case let .number(number):
      hasher.combine(number)
    case let .integer(integer):
      hasher.combine(integer)
    case let .boolean(boolean):
      hasher.combine(boolean)
    case let .string(string):
      hasher.combine(string)
    case let .array(array):
      hasher.combine(array)
    case let .object(object):
      hasher.combine(object)
    case .null:
      break
    }
  }
}

extension JSONValue: CustomStringConvertible {
  public var description: String {
    switch self {
    case .null:
      return "null"
    case let .number(number):
      return number.description
    case let .integer(integer):
      return integer.description
    case let .boolean(boolean):
      return boolean ? "true" : "false"
    case let .string(string):
      return "\"\(string)\""
    case let .array(array):
      return "[\(array.map { $0.description }.joined(separator: ", "))]"
    case let .object(object):
      return
        "[\(object.map { (key, value) in "\"\(key)\": \(value.description)" }.joined(separator: ", "))]"
    }
  }
}

extension JSONValue: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .null:
      return "JSONValue(null)"
    case let .number(number):
      return "JSONValue(\(number.debugDescription))"
    case let .integer(integer):
      return "JSONValue(\(integer.description))"
    case let .boolean(boolean):
      return "JSONValue(\(boolean ? "true" : "false"))"
    case let .string(string):
      return "JSONValue(\"\(string)\")"
    case let .array(array):
      return "JSONValue([\(array.map { $0.debugDescription }.joined(separator: ", "))])"
    case let .object(object):
      return
        "JSONValue([\(object.map { (key, value) in "\"\(key)\": \(value.debugDescription)" }.joined(separator: ", "))])"
    }
  }
}

extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) {
    self = .null
  }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: BooleanLiteralType) {
    self = .boolean(value)
  }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral,
  ExpressibleByExtendedGraphemeClusterLiteral
{
  public init(stringLiteral value: StringLiteralType) {
    self = .string(value)
  }

  public init(unicodeScalarLiteral value: String) {
    self = .string(value)
  }

  public init(extendedGraphemeClusterLiteral value: String) {
    self = .string(value)
  }
}

extension JSONValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: FloatLiteralType) {
    self = .number(value)
  }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: IntegerLiteralType) {
    self = .integer(Int64(value))
  }
}

extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: any JSONRepresentable...) {
    self = .array(elements.map { $0.jsonValue })
  }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, any JSONRepresentable)...) {
    self = .object(
      [String: JSONValue](
        elements.map { (key, value) in (key, value.jsonValue) },
        uniquingKeysWith: { (first, _) in first }
      ))
  }
}

extension Bool: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .boolean(self)
  }
}

extension String: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .string(self)
  }
}

extension Double: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .number(self)
  }
}

extension Float: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .number(Double(self))
  }
}

extension Int: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .integer(Int64(self))
  }
}

extension Int8: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .integer(Int64(self))
  }
}

extension Int16: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .integer(Int64(self))
  }
}

extension Int32: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .integer(Int64(self))
  }
}

extension Int64: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .integer(self)
  }
}

extension UInt8: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .integer(Int64(self))
  }
}

extension UInt16: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .integer(Int64(self))
  }
}

extension UInt32: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .integer(Int64(self))
  }
}

extension Array: JSONRepresentable where Element: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .array(self.map { $0.jsonValue })
  }
}

extension Dictionary: JSONRepresentable where Key == String, Value: JSONRepresentable {
  public var jsonValue: JSONValue {
    return .object(self.mapValues { $0.jsonValue })
  }
}

// MARK: - Convenience Properties

extension JSONValue {
  /// Returns true if this value is null
  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }
}
