// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
public import Dependencies

extension OAuthClient: @retroactive DependencyKey {
  static let liveValue = OAuthClient()
}

extension DependencyValues {
  var oauthClient: OAuthClient {
    get { self[OAuthClient.self] }
    set { self[OAuthClient.self] = newValue }
  }
}
