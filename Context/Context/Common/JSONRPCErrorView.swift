// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct JSONRPCErrorView: View {
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
          // Check if the error message contains JSON and format it
          let formattedMessage = JSONRPCErrorFormatter.formatErrorMessage(
            jsonRPCError.error.message)
          Text("**Error \(String(jsonRPCError.error.code)):** \(formattedMessage)")
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

          if let data = jsonRPCError.error.data {
            let formattedData = JSONRPCErrorFormatter.formatPreview(data)
            let lines = formattedData.components(separatedBy: "\n")

            if lines.count > 1 {
              // Multi-line error details
              VStack(alignment: .leading, spacing: 4) {
                Text("Details:")
                  .font(.caption)
                  .fontWeight(.medium)
                  .foregroundColor(.secondary)
                  .padding(.top, 4)

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
              }
            } else {
              // Single line error details
              Text("Details:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.top, 4)

              Text(formattedData)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
            }
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
struct JSONRPCErrorFormatter {
  static func formatErrorMessage(_ message: String) -> String {
    // First check if the message itself contains JSON
    if JSONUtility.isLikelyJSON(message), let data = message.data(using: .utf8),
      let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data)
    {
      // If it's an array of validation errors, format them nicely
      if case .array(let arr) = jsonValue, isValidationErrorArray(arr) {
        let errors = arr.compactMap { item -> String? in
          guard case .object(let obj) = item else { return nil }
          if case .string(let msg) = obj["message"] {
            return msg
          }
          return nil
        }
        if !errors.isEmpty {
          return errors.joined(separator: ", ")
        }
      }
      return formatPreview(jsonValue)
    }
    return message
  }

  static func formatPreview(_ value: JSONValue) -> String {
    switch value {
    case .string(let str):
      // Check if the string contains JSON and try to parse it
      if JSONUtility.isLikelyJSON(str), let formattedJSON = parseAndFormatJSONString(str) {
        return formattedJSON
      }
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
      return formatArrayPreview(arr)
    case .object(let obj):
      return formatObjectPreview(obj)
    }
  }

  private static func parseAndFormatJSONString(_ jsonString: String) -> String? {
    guard let data = jsonString.data(using: .utf8),
      let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data)
    else {
      return nil
    }

    // Format the parsed JSON value
    switch jsonValue {
    case .array(let arr):
      return formatArrayPreview(arr)
    case .object(let obj):
      return formatObjectPreview(obj)
    default:
      return formatPreview(jsonValue)
    }
  }

  private static func formatArrayPreview(_ arr: [JSONValue]) -> String {
    // For validation errors, format them nicely
    if isValidationErrorArray(arr) {
      return arr.compactMap { item -> String? in
        guard case .object(let obj) = item else { return nil }

        // Extract validation error details
        var parts: [String] = []

        if case .string(let path) = obj["path"] {
          parts.append("Path: \(path)")
        } else if case .array(let pathArray) = obj["path"], !pathArray.isEmpty {
          let pathStr = pathArray.compactMap { pathItem -> String? in
            if case .string(let s) = pathItem { return s }
            if case .integer(let i) = pathItem { return String(i) }
            return nil
          }.joined(separator: ".")
          if !pathStr.isEmpty {
            parts.append("Path: \(pathStr)")
          }
        }

        if case .string(let message) = obj["message"] {
          parts.append(message)
        }

        if case .string(let code) = obj["code"] {
          parts.append("(\(code))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
      }.joined(separator: "\n")
    }

    // Default array formatting
    return "[\(arr.count) items]"
  }

  private static func formatObjectPreview(_ obj: [String: JSONValue]) -> String {
    // Check if this is a single validation error
    if let message = obj["message"], case .string(let msg) = message {
      var parts: [String] = [msg]

      if let code = obj["code"], case .string(let codeStr) = code {
        parts.append("(\(codeStr))")
      }

      return parts.joined(separator: " ")
    }

    return "{\(obj.count) properties}"
  }

  private static func isValidationErrorArray(_ arr: [JSONValue]) -> Bool {
    // Check if this looks like an array of validation errors
    guard !arr.isEmpty else { return false }

    // Check first item to see if it has validation error structure
    if case .object(let obj) = arr.first {
      return obj["message"] != nil || obj["code"] != nil
    }

    return false
  }

}
