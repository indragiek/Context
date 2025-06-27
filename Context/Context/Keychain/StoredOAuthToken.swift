// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation

/// Wrapper that stores an OAuth token along with the client ID used to obtain it.
struct StoredOAuthToken: Codable {
  let token: OAuthToken
  let clientID: String

  init(token: OAuthToken, clientID: String) {
    self.token = token
    self.clientID = clientID
  }
}
