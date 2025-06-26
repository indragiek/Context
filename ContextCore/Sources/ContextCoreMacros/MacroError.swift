// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// A custom error type for handling macro-related errors.
struct MacroError: Error, LocalizedError, Equatable {
  let errorDescription: String?

  init(_ errorDescription: String) {
    self.errorDescription = errorDescription
  }
}
