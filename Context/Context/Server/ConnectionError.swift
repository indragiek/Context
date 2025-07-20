// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

struct ConnectionError: Equatable, Identifiable {
  let id = UUID()
  let error: String
  let timestamp: Date

  init(error: any Error) {
    self.error = error.localizedDescription
    self.timestamp = Date()
  }

  init(message: String) {
    self.error = message
    self.timestamp = Date()
  }
}
