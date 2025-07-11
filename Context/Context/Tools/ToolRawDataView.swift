// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

/// A wrapper for ToolDetailView that uses the common RawDataView
struct ToolRawDataView: View {
  let rawResponseJSON: JSONValue?
  let rawResponseError: String?
  let underlyingError: (any Error)?
  
  var body: some View {
    RawDataView(
      rawResponseJSON: rawResponseJSON,
      rawResponseError: rawResponseError,
      underlyingError: underlyingError
    )
  }
}

// Extension to maintain compatibility with existing code
extension ToolRawDataView {
  static func copyRawDataToClipboard(
    rawResponseJSON: JSONValue?,
    underlyingError: (any Error)?
  ) {
    RawDataView.copyRawDataToClipboard(
      rawResponseJSON: rawResponseJSON,
      underlyingError: underlyingError
    )
  }
}