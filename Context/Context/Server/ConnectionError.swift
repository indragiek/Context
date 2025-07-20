// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation

struct ConnectionError: Equatable, Identifiable {
  let id = UUID()
  let errorDescription: String
  let json: JSONValue?
  let timestamp: Date

  init(error: any Error) {
    let (description, extractedJSON) = JSONUtility.extractErrorAndJSON(from: error)
    self.errorDescription = description
    self.json = extractedJSON
    self.timestamp = Date()
  }

  init(message: String) {
    self.errorDescription = message
    self.json = nil
    self.timestamp = Date()
  }
}
