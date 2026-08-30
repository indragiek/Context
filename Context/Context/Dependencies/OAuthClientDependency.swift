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

struct OAuthTransactionGenerator: Sendable {
  var generateState: @Sendable () throws -> OAuthClient.StateParameter
  var generatePKCE: @Sendable () throws -> OAuthClient.PKCEParameters
}

extension OAuthTransactionGenerator: DependencyKey {
  static let liveValue = OAuthTransactionGenerator(
    generateState: OAuthClient.StateParameter.generate,
    generatePKCE: OAuthClient.PKCEParameters.generate
  )
}

extension DependencyValues {
  var oauthTransactionGenerator: OAuthTransactionGenerator {
    get { self[OAuthTransactionGenerator.self] }
    set { self[OAuthTransactionGenerator.self] = newValue }
  }
}
