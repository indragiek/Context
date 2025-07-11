// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

/// A wrapper for ToolDetailView that uses the common RawDataView
struct ToolRawDataView: View {
  let responseJSON: JSONValue?
  let responseError: (any Error)?
  
  var body: some View {
    RawDataView(
      responseJSON: responseJSON,
      responseError: responseError
    )
  }
}

// Extension to maintain compatibility with existing code
extension ToolRawDataView {
  static func copyRawDataToClipboard(
    responseJSON: JSONValue?,
    responseError: (any Error)?
  ) {
    RawDataView.copyRawDataToClipboard(
      responseJSON: responseJSON,
      responseError: responseError
    )
  }
}