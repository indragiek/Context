// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation

struct LogEntry: Identifiable, Equatable {
  let id = UUID()
  let params: LoggingMessageNotification.Params
  let timestamp: Date

  init(params: LoggingMessageNotification.Params, timestamp: Date = Date()) {
    self.params = params
    self.timestamp = timestamp
  }
}
