// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

enum OAuthConstants {
  static let callbackURL = URL(string: "app.contextmcp://oauth/callback")!
  
  static var urlScheme: String {
    callbackURL.scheme!
  }
  
  static var callbackHost: String {
    callbackURL.host!
  }
  
  static var callbackPath: String {
    callbackURL.path
  }
}