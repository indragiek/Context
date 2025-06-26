// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// Represents a connection-related error that can be resolved by reconnecting
struct NotConnectedError: Error, Equatable, LocalizedError, CustomStringConvertible,
  CustomDebugStringConvertible
{
  private static let defaultDescription = "Server is not connected"

  let underlyingError: (any Error)?

  init(underlyingError: (any Error)? = nil) {
    self.underlyingError = underlyingError
  }

  var localizedDescription: String {
    return underlyingError?.localizedDescription ?? Self.defaultDescription
  }

  // MARK: LocalizedError

  var errorDescription: String? {
    return (underlyingError as? (any LocalizedError))?.errorDescription
  }

  var failureReason: String? {
    return (underlyingError as? (any LocalizedError))?.failureReason
  }

  var recoverySuggestion: String? {
    return (underlyingError as? (any LocalizedError))?.recoverySuggestion
  }

  var helpAnchor: String? {
    return (underlyingError as? (any LocalizedError))?.helpAnchor
  }

  // MARK: CustomStringConvertible

  var description: String {
    return (underlyingError as? (any CustomStringConvertible))?.description
      ?? Self.defaultDescription
  }

  // MARK: CustomDebugStringConvertible

  var debugDescription: String {
    return (underlyingError as? (any CustomDebugStringConvertible))?.debugDescription
      ?? Self.defaultDescription
  }

  // MARK: Equatable

  static func == (lhs: NotConnectedError, rhs: NotConnectedError) -> Bool {
    return String(reflecting: lhs) == String(reflecting: rhs)
  }
}

private let connectionKeywords = ["connect", "disconnect", "transport", "closed", "authentication"]

extension Error {
  var isLikelyConnectionError: Bool {
    let errorDescription = localizedDescription.lowercased()
    return connectionKeywords.contains { errorDescription.contains($0) }
  }
}
