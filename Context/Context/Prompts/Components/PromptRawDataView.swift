// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

/// A wrapper for PromptDetailView that uses the common RawDataView
struct PromptRawDataView: View {
  let promptState: PromptState
  
  var body: some View {
    RawDataView(
      rawResponseJSON: promptState.rawResponseJSON,
      rawResponseError: promptState.rawResponseError,
      underlyingError: promptState.loadingState.underlyingError
    )
  }
}

extension PromptLoadingState {
  var underlyingError: (any Error)? {
    switch self {
    case .failed(_, let error):
      return error
    default:
      return nil
    }
  }
}
