// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct PromptRawDataView: View {
  let promptState: PromptState
  
  var body: some View {
    if let error = promptState.loadingState.underlyingError {
      errorRawView(for: error)
    } else if let jsonValue = promptState.rawResponseJSON {
      JSONRawView(jsonValue: jsonValue, searchText: "", isSearchActive: false)
    } else if let error = promptState.rawResponseError {
      jsonErrorView(error)
    } else {
      emptyRawView
    }
  }
  
  @ViewBuilder
  private func errorRawView(for error: any Error) -> some View {
    if let clientError = error as? ClientError {
      switch clientError {
      case .requestFailed(_, let jsonRPCError):
        // For requestFailed, show the JSONRPCError in JSONRawView
        if let jsonData = try? JSONEncoder().encode(jsonRPCError),
           let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData) {
          JSONRawView(jsonValue: jsonValue, searchText: "", isSearchActive: false)
        } else {
          errorPlaceholder
        }
        
      case .requestInvalidResponse(_, _, let data):
        // For invalid response, check if the data is valid JSON
        if let stringData = String(data: data, encoding: .utf8) {
          if JSONRPCErrorFormatter.isLikelyJSON(stringData) {
            // Try to parse as JSON
            if let jsonData = stringData.data(using: .utf8),
               let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData) {
              JSONRawView(jsonValue: jsonValue, searchText: "", isSearchActive: false)
            } else {
              // Show as plain text if JSON parsing fails
              plainTextView(stringData)
            }
          } else {
            // Show as plain text if not JSON-like
            plainTextView(stringData)
          }
        } else {
          errorPlaceholder
        }
        
      default:
        errorPlaceholder
      }
    } else {
      errorPlaceholder
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
  
  private func jsonErrorView(_ error: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.largeTitle)
        .foregroundColor(.red)
      
      Text("JSON Error")
        .font(.headline)
      
      Text(error)
        .font(.callout)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  
  private var errorPlaceholder: some View {
    ContentUnavailableView(
      "No Error Object",
      systemImage: "xmark.circle",
      description: Text("An error object was not returned by the server")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  
  private var emptyRawView: some View {
    Text("No raw data available")
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private extension PromptLoadingState {
  var underlyingError: (any Error)? {
    switch self {
    case .failed(_, let error):
      return error
    default:
      return nil
    }
  }
}
