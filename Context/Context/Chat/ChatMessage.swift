// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

struct ChatMessage: Identifiable, Equatable {
  let id = UUID()
  let content: String
  let isFromUser: Bool
  let timestamp: Date
}
