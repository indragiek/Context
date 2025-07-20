// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

/// A common view for displaying raw JSON data, errors, and empty states
/// Used by both ToolDetailView and PromptDetailView
struct RawDataView: View {
  let responseJSON: JSONValue?
  let responseError: (any Error)?

  var body: some View {
    if let error = responseError {
      errorRawView(for: error)
    } else if let jsonValue = responseJSON {
      JSONRawView(jsonValue: jsonValue, searchText: "", isSearchActive: false)
    } else {
      emptyRawView
    }
  }

  @ViewBuilder
  private func errorRawView(for error: any Error) -> some View {
    let (errorDescription, extractedJSON) = JSONUtility.extractErrorAndJSON(from: error)
    
    if let jsonValue = extractedJSON {
      JSONRawView(jsonValue: jsonValue, searchText: "", isSearchActive: false)
    } else {
      if !errorDescription.isEmpty {
        plainTextView(errorDescription)
      } else {
        errorPlaceholder
      }
    }
  }

  private func plainTextView(_ text: String) -> some View {
    ScrollView {
      Text(text)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var errorPlaceholder: some View {
    ContentUnavailableView(
      "No Error Details",
      systemImage: "xmark.circle",
      description: Text("No error details available")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyRawView: some View {
    Text("No raw data available")
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
