// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation

// Import LogEntry from the same module
// LogEntry is defined in LogEntry.swift

/// A wrapper around LogEntry that caches the JSON-encoded string representation and search text
struct CachedLogEntry: Identifiable, Equatable {
  let logEntry: LogEntry
  let jsonString: String
  let searchText: String  // Lowercase version for fast searching

  var id: UUID { logEntry.id }

  init(_ logEntry: LogEntry) {
    self.logEntry = logEntry

    // Encode JSON once during initialization
    if let string = JSONUtility.prettyString(from: logEntry.params, escapeSlashes: true) {
      self.jsonString = string
      self.searchText = string.lowercased()
    } else {
      self.jsonString = "Unable to encode log entry"
      self.searchText = "unable to encode log entry"
    }
  }

  /// Returns true if this log entry contains the search query (case-insensitive)
  func contains(searchQuery: String) -> Bool {
    searchText.contains(searchQuery.lowercased())
  }
}
