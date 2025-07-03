// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

struct URLHelpers {
  static func extractHostName(from urlString: String) -> String? {
    // Use URLComponents for more robust URL parsing
    guard let urlComponents = URLComponents(string: urlString),
      let host = urlComponents.host
    else {
      return nil
    }

    // Remove common subdomains and TLDs to extract the main domain name
    let components = host.components(separatedBy: ".")

    // Handle cases like "example.com" or "sub.example.com" or "example.co.uk"
    if components.count >= 2 {
      // Find the main domain part (usually the second-to-last component before TLD)
      // For simplicity, we'll take the component before the last dot(s)
      // This handles most common cases
      if components.count == 2 {
        // Simple case: example.com -> example
        return components[0]
      } else {
        // More complex case: Try to identify the main domain
        // Common TLDs and second-level domains
        let commonTLDs = ["com", "net", "org", "io", "dev", "app", "co", "gov", "edu", "mil"]

        // Check if second-to-last is a common TLD (like .co in .co.uk)
        if components.count >= 3 && commonTLDs.contains(components[components.count - 2]) {
          // Case like example.co.uk -> example
          return components[components.count - 3]
        } else {
          // Case like sub.example.com -> example
          return components[components.count - 2]
        }
      }
    }

    // Fallback: return the whole host without port
    return host
  }
}
