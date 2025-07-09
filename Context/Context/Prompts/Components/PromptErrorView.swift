// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct PromptErrorView: View {
  let error: any Error
  
  var body: some View {
    if let clientError = error as? ClientError {
      clientErrorView(clientError)
    } else {
      genericErrorView
    }
  }
  
  @ViewBuilder
  private func clientErrorView(_ error: ClientError) -> some View {
    switch error {
    case .requestFailed(_, let jsonRPCError):
      ContentUnavailableView {
        Label("Request Failed", systemImage: "exclamationmark.triangle")
      } description: {
        VStack(spacing: 8) {
          Text("**Error \(String(jsonRPCError.error.code)):** \(jsonRPCError.error.message)")
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
          
          if let data = jsonRPCError.error.data {
            Text("Details:")
              .font(.caption)
              .fontWeight(.medium)
              .foregroundColor(.secondary)
              .padding(.top, 4)
            
            Text(JSONValueFormatter.formatPreview(data))
              .font(.system(.caption, design: .monospaced))
              .foregroundColor(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
              .textSelection(.enabled)
          }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 400)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      
    case .requestInvalidResponse(_, let underlyingError, let data):
      ContentUnavailableView {
        Label("Invalid Response", systemImage: "exclamationmark.triangle")
      } description: {
        VStack(spacing: 8) {
          Text(underlyingError.localizedDescription)
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
          
          if let stringData = String(data: data, encoding: .utf8) {
            Text("Response data:")
              .font(.caption)
              .fontWeight(.medium)
              .foregroundColor(.secondary)
              .padding(.top, 4)
            
            Text(stringData)
              .font(.system(.caption, design: .monospaced))
              .foregroundColor(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
              .textSelection(.enabled)
          }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 400)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      
    default:
      genericErrorView
    }
  }
  
  private var genericErrorView: some View {
    ContentUnavailableView(
      "Error",
      systemImage: "exclamationmark.triangle",
      description: Text(error.localizedDescription)
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Utility for formatting JSON values for display
struct JSONValueFormatter {
  static func formatPreview(_ value: JSONValue) -> String {
    switch value {
    case .string(let str):
      return str
    case .number(let num):
      return String(num)
    case .integer(let int):
      return String(int)
    case .boolean(let bool):
      return String(bool)
    case .null:
      return "null"
    case .array(let arr):
      return "[\(arr.count) items]"
    case .object(let obj):
      return "{\(obj.count) properties}"
    }
  }
  
  static func isLikelyJSON(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
  }
}