// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import ContextCore

#if canImport(ContextCoreMacros)
  import ContextCoreMacros

  let testMacros: [String: Macro.Type] = [
    "JSONRPCRequest": JSONRPCRequestMacro.self,
    "JSONRPCNotification": JSONRPCNotificationMacro.self,
    "JSONRPCResponse": JSONRPCResponseMacro.self,
  ]
#endif

final class JSONRPCMacrosTests: XCTestCase {
  func testJSONRPCRequestMacro() throws {
    #if canImport(ContextCoreMacros)
      assertMacroExpansion(
        """
        @JSONRPCRequest(method: "test", responseType: TestResponse.self)
        public struct TestRequest {
            public struct Params: Codable {
                let name: String
            }
        }
        """,
        expandedSource: """
          public struct TestRequest {
              public struct Params: Codable {
                  let name: String
              }

              public let jsonrpc: String

              public let method: String

              public let params: Params

              public let id: JSONRPCRequestID

              public let responseDecoder: ResponseDecoder = { decoder, data in
                  return try decoder.decode(TestResponse.self, from: data)
              }

              public init(id: JSONRPCRequestID, name: String) {
                  self.jsonrpc = "2.0"
                  self.method = "test"
                  self.params = Params(name: name)
                  self.id = id
              }

              enum CodingKeys: String, CodingKey {
                  case jsonrpc
                  case method
                  case params
                  case id
              }

              public typealias Response = TestResponse

              public var debugDescription: String {
                  \"\"\"
                  TestRequest {
                      method="\\(method)",
                      id=\\(String(reflecting: id)),
                      params={
                          name=\\(String(reflecting: self.params.name))
                      }
                  }
                  \"\"\"
              }

              public var description: String {
                  \"\"\"
                  TestRequest {
                      method="\\(method)",
                      id=\\(String(reflecting: id)),
                      params=...
                  }
                  \"\"\"
              }
          }

          extension TestRequest: JSONRPCRequest, Codable, CustomDebugStringConvertible, CustomStringConvertible {
          }
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testJSONRPCNotificationMacro() throws {
    #if canImport(ContextCoreMacros)
      assertMacroExpansion(
        """
        @JSONRPCNotification(method: "test")
        public struct TestNotification {
            public struct Params: Codable {
                let name: String
            }
        }
        """,
        expandedSource: """
          public struct TestNotification {
              public struct Params: Codable {
                  let name: String
              }

              public let jsonrpc: String

              public let method: String

              public let params: Params

              public init(name: String) {
                  self.jsonrpc = "2.0"
                  self.method = "test"
                  self.params = Params(name: name)
              }

              enum CodingKeys: String, CodingKey {
                  case jsonrpc
                  case method
                  case params
              }

              public var debugDescription: String {
                  \"\"\"
                  TestNotification {
                      method=\"\\(method)\",
                      params={
                          name=\\(String(reflecting: self.params.name))
                      }
                  }
                  \"\"\"
              }

              public var description: String {
                  \"\"\"
                  TestNotification {
                      method="\\(method)",
                      params=...
                  }
                  \"\"\"
              }
          }

          extension TestNotification: JSONRPCNotification, Codable, CustomDebugStringConvertible, CustomStringConvertible {
          }
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testJSONRPCResponseMacro() throws {
    #if canImport(ContextCoreMacros)
      assertMacroExpansion(
        """
        @JSONRPCResponse
        public struct TestResponse {
            public struct Result: Codable {
                let value: Int
            }
        }
        """,
        expandedSource: """
          public struct TestResponse {
              public struct Result: Codable {
                  let value: Int
              }

              public let jsonrpc: String

              public let result: Result

              public let id: JSONRPCRequestID

              public init(id: JSONRPCRequestID, value: Int) {
                  self.jsonrpc = "2.0"
                  self.result = Result(value: value)
                  self.id = id
              }

              enum CodingKeys: String, CodingKey {
                  case jsonrpc
                  case result
                  case id
              }

              public var debugDescription: String {
                  \"\"\"
                  TestResponse {
                      id=\\(String(reflecting: id)),
                      result={
                          value=\\(String(reflecting: self.result.value))
                      }
                  }
                  \"\"\"
              }

              public var description: String {
                  \"\"\"
                  TestResponse {
                      id=\\(String(reflecting: id)),
                      result=...
                  }
                  \"\"\"
              }
          }

          extension TestResponse: JSONRPCResponse, Codable, CustomDebugStringConvertible, CustomStringConvertible {
          }
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }
}
