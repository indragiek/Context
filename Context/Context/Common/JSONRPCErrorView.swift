// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct JSONRPCErrorView: View {
  let error: any Error

  var body: some View {
    ContentUnavailableView {
      Label("Error", systemImage: "exclamationmark.triangle")
    } description: {
      VStack(spacing: 8) {
        let (errorDescription, extractedJSON) = JSONUtility.extractErrorAndJSON(from: error)
        
        Text(errorDescription)
          .font(.callout)
          .foregroundColor(.secondary)

        if let jsonValue = extractedJSON {
          jsonErrorDetailsView(jsonValue)
        }
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: 400)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  
  @ViewBuilder
  private func jsonErrorDetailsView(_ jsonValue: JSONValue) -> some View {
    let formattedData = formatJSONValue(jsonValue)
    let lines = formattedData.components(separatedBy: "\n")
    
    VStack(alignment: .leading, spacing: 4) {
      Text("Details:")
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
        .padding(.top, 4)
      
      if lines.count > 1 {
        // Multi-line error details
        VStack(alignment: .leading, spacing: 2) {
          ForEach(Array(lines.prefix(5).enumerated()), id: \.offset) { _, line in
            Text(line)
              .font(.system(.caption, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
          }
          
          if lines.count > 5 {
            Text("... and \(lines.count - 5) more")
              .font(.caption)
              .foregroundColor(Color.secondary.opacity(0.6))
          }
        }
      } else {
        // Single line error details
        Text(formattedData)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(3)
          .textSelection(.enabled)
      }
    }
  }
  
  private func formatJSONValue(_ value: JSONValue) -> String {
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
      // For arrays, show a simple summary
      return "[\(arr.count) items]"
    case .object(let obj):
      // For objects, try to extract meaningful information
      if let message = obj["message"], case .string(let msg) = message {
        var result = msg
        if let code = obj["code"] {
          result += " (code: \(formatJSONValue(code)))"
        }
        return result
      }
      return "{\(obj.count) properties}"
    }
  }
}