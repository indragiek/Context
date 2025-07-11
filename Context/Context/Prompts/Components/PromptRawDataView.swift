// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

/// A wrapper for PromptDetailView that uses the common RawDataView
struct PromptRawDataView: View {
  let promptState: PromptState
  
  var body: some View {
    RawDataView(
      responseJSON: promptState.responseJSON,
      responseError: promptState.responseError
    )
  }
}
