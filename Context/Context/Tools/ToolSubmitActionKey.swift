// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ToolSubmitActionKey: EnvironmentKey {
  static let defaultValue: (@Sendable () -> Void)? = nil
}

extension EnvironmentValues {
  var toolSubmitAction: (@Sendable () -> Void)? {
    get { self[ToolSubmitActionKey.self] }
    set { self[ToolSubmitActionKey.self] = newValue }
  }
}
