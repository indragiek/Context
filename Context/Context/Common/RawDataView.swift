// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import ContextCore
import SwiftUI
import os

/// A common view for displaying raw JSON data, errors, and empty states
/// Used by both ToolDetailView and PromptDetailView
struct RawDataView: View {
  private static let logger = Logger(subsystem: "com.indragie.Context", category: "RawDataView")
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
    if let clientError = error as? ClientError {
      switch clientError {
      case .requestFailed(_, let jsonRPCError):
        // For requestFailed, show the JSONRPCError in JSONRawView
        if let jsonData = try? JSONEncoder().encode(jsonRPCError),
          let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData)
        {
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
              let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: jsonData)
            {
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

// MARK: - Clipboard Support

extension RawDataView {
  /// Copies raw data to clipboard, handling both JSON responses and errors
  static func copyRawDataToClipboard(
    responseJSON: JSONValue?,
    responseError: (any Error)?
  ) {
    // Try to copy raw response JSON first
    if let jsonValue = responseJSON {
      if let jsonString = JSONUtility.prettyString(from: jsonValue) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonString, forType: .string)
      } else {
        logger.error("Failed to encode JSON for clipboard")
      }
      return
    }

    // If no raw response, try to copy error data
    if let error = responseError {
      if let clientError = error as? ClientError {
        switch clientError {
        case .requestFailed(_, let jsonRPCError):
          // Copy the JSON-RPC error
          if let jsonString = JSONUtility.prettyString(from: jsonRPCError) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonString, forType: .string)
          } else {
            logger.error("Failed to encode error JSON for clipboard")
          }

        case .requestInvalidResponse(_, _, let data):
          // Copy the raw response data
          if let stringData = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(stringData, forType: .string)
          }

        default:
          // Copy error description as fallback
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(error.localizedDescription, forType: .string)
        }
      } else {
        // Copy error description for non-ClientError
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(error.localizedDescription, forType: .string)
      }
    }
  }
}
