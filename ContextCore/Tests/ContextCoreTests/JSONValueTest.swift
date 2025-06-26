// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite(.timeLimit(.minutes(1))) struct JSONValueTest {
  @Test func testEncodeDecodeNull() async throws {
    let null = JSONValue.null
    let json = try null.encodeString()
    #expect(json == "null")
    #expect(try JSONValue(decoding: json) == null)
  }

  @Test func testEncodeDecodeNumber() async throws {
    let number = JSONValue.number(Double.greatestFiniteMagnitude)
    let json = try number.encodeString()
    #expect(json == "\(Double.greatestFiniteMagnitude)")
    #expect(try JSONValue(decoding: json) == number)
  }

  @Test func testEncodeDecodeInteger() async throws {
    let integer = JSONValue.integer(Int64.max)
    let json = try integer.encodeString()
    #expect(json == "\(Int64.max)")
    #expect(try JSONValue(decoding: json) == integer)
  }

  @Test func testEncodeDecodeBool() async throws {
    let boolean = JSONValue.boolean(true)
    let json = try boolean.encodeString()
    #expect(json == "true")
    #expect(try JSONValue(decoding: json) == boolean)
  }

  @Test func testEncodeDecodeString() async throws {
    let string = JSONValue.string("hello, world")
    let json = try string.encodeString()
    #expect(json == "\"hello, world\"")
    #expect(try JSONValue(decoding: json) == string)
  }

  @Test func testEncodeDecodeArray() async throws {
    let array = JSONValue.array([1, "test", 2, true])
    let json = try array.encodeString()
    #expect(json == "[1,\"test\",2,true]")
    #expect(try JSONValue(decoding: json) == array)
  }

  @Test func testEncodeDecodeObject() async throws {
    let object = JSONValue.object(["key1": true, "key2": "test"])
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = try object.encodeString(encoder: encoder)
    #expect(json == "{\"key1\":true,\"key2\":\"test\"}")
    #expect(try JSONValue(decoding: json) == object)
  }

  @Test func testEncodeDecodeNestedObject() async throws {
    let object = JSONValue.object(["key1": [1, "test", 2, true], "key2": "test"])
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = try object.encodeString(encoder: encoder)
    #expect(json == "{\"key1\":[1,\"test\",2,true],\"key2\":\"test\"}")
    #expect(try JSONValue(decoding: json) == object)
  }

  @Test func testInitWithNilLiteral() async throws {
    let null: JSONValue = nil
    let json = try null.encodeString()
    #expect(json == "null")
    #expect(try JSONValue(decoding: json) == null)
  }

  @Test func testInitWithBoolLiteral() async throws {
    let boolean: JSONValue = true
    let json = try boolean.encodeString()
    #expect(json == "true")
    #expect(try JSONValue(decoding: json) == boolean)
  }

  @Test func testInitWithStringLiteral() async throws {
    let string: JSONValue = "hello, world"
    let json = try string.encodeString()
    #expect(json == "\"hello, world\"")
    #expect(try JSONValue(decoding: json) == string)
  }

  @Test func testInitWithFloatLiteral() async throws {
    let float: JSONValue = 3.14159
    let json = try float.encodeString()
    #expect(json == "3.14159")
    #expect(try JSONValue(decoding: json) == float)
  }

  @Test func testInitWithArrayLiteral() async throws {
    let array: JSONValue = [1, "test", 2, true]
    let json = try array.encodeString()
    #expect(json == "[1,\"test\",2,true]")
    #expect(try JSONValue(decoding: json) == array)
  }

  @Test func testInitWithDictionaryLiteral() async throws {
    let object: JSONValue = ["key1": [1, "test", 2, true] as [JSONValue], "key2": "test"]
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = try object.encodeString(encoder: encoder)
    #expect(json == "{\"key1\":[1,\"test\",2,true],\"key2\":\"test\"}")
    #expect(try JSONValue(decoding: json) == object)
  }
}
