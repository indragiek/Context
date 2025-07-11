// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation

// State for individual tool (arguments and responses)
struct ToolState: Sendable {
  var parameterValues: [String: JSONValue] = [:]
  var toolResponse: CallToolResponse.Result?
  var hasLoadedOnce = false
  var responseJSON: JSONValue?
  var responseError: (any Error)?
}

// Manual Equatable conformance
extension ToolState: Equatable {
  static func == (lhs: ToolState, rhs: ToolState) -> Bool {
    // Compare Equatable properties
    guard lhs.parameterValues == rhs.parameterValues && 
          lhs.hasLoadedOnce == rhs.hasLoadedOnce &&
          lhs.responseJSON == rhs.responseJSON else {
      return false
    }
    
    // Compare errors by their existence and type
    let lhsErrorType = lhs.responseError.map { type(of: $0) }
    let rhsErrorType = rhs.responseError.map { type(of: $0) }
    let lhsErrorMessage = lhs.responseError?.localizedDescription
    let rhsErrorMessage = rhs.responseError?.localizedDescription
    
    return lhsErrorType == rhsErrorType && lhsErrorMessage == rhsErrorMessage
    // Note: toolResponse is excluded from equality check since it's not Equatable
  }
}

// TCA Dependency
extension DependencyValues {
  var toolCache: LRUCache<String, ToolState> {
    get { self[ToolCacheKey.self] }
    set { self[ToolCacheKey.self] = newValue }
  }
}

private enum ToolCacheKey: DependencyKey {
  static let liveValue = LRUCache<String, ToolState>(maxSize: 25)
  static let testValue = LRUCache<String, ToolState>(maxSize: 25)
}
