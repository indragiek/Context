// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Dependencies

// MARK: - Dependency Key

extension DXTConfigKeychain: DependencyKey {
  static let liveValue = DXTConfigKeychain()
}

extension DependencyValues {
  var dxtConfigKeychain: DXTConfigKeychain {
    get { self[DXTConfigKeychain.self] }
    set { self[DXTConfigKeychain.self] = newValue }
  }
}