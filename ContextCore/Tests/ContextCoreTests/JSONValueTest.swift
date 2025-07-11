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
  
  @Test func testEquatable() async throws {
    // Test null equality
    #expect(JSONValue.null == JSONValue.null)
    
    // Test number equality
    #expect(JSONValue.number(3.14) == JSONValue.number(3.14))
    #expect(JSONValue.number(3.14) != JSONValue.number(2.71))
    
    // Test integer equality
    #expect(JSONValue.integer(42) == JSONValue.integer(42))
    #expect(JSONValue.integer(42) != JSONValue.integer(24))
    
    // Test boolean equality
    #expect(JSONValue.boolean(true) == JSONValue.boolean(true))
    #expect(JSONValue.boolean(true) != JSONValue.boolean(false))
    
    // Test string equality
    #expect(JSONValue.string("hello") == JSONValue.string("hello"))
    #expect(JSONValue.string("hello") != JSONValue.string("world"))
    
    // Test array equality
    #expect(JSONValue.array([1, "test", true]) == JSONValue.array([1, "test", true]))
    #expect(JSONValue.array([1, "test", true]) != JSONValue.array([1, "test", false]))
    #expect(JSONValue.array([1, 2, 3]) != JSONValue.array([1, 2]))
    
    // Test object equality
    #expect(JSONValue.object(["a": 1, "b": "test"]) == JSONValue.object(["a": 1, "b": "test"]))
    #expect(JSONValue.object(["a": 1, "b": "test"]) != JSONValue.object(["a": 2, "b": "test"]))
    #expect(JSONValue.object(["a": 1]) != JSONValue.object(["a": 1, "b": 2]))
    
    // Test different types are not equal
    #expect(JSONValue.null != JSONValue.number(0))
    #expect(JSONValue.integer(1) != JSONValue.number(1.0))
    #expect(JSONValue.string("true") != JSONValue.boolean(true))
    #expect(JSONValue.array([]) != JSONValue.object([:]))
    
    // Test nested structures
    let nested1 = JSONValue.object([
      "array": .array([1, 2, .object(["nested": true])]),
      "string": "value"
    ])
    let nested2 = JSONValue.object([
      "array": .array([1, 2, .object(["nested": true])]),
      "string": "value"
    ])
    let nested3 = JSONValue.object([
      "array": .array([1, 2, .object(["nested": false])]),
      "string": "value"
    ])
    #expect(nested1 == nested2)
    #expect(nested1 != nested3)
  }
}
