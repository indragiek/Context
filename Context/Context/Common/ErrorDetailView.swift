// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ErrorDetailView: View {
  let error: any Error
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Title
      Text(errorTitle)
        .font(.headline)
        .bold()
        .lineLimit(.max)
        .multilineTextAlignment(.leading)

      // Body sections
      VStack(alignment: .leading, spacing: 8) {
        if let decodingError = error as? DecodingError {
          decodingErrorBody(for: decodingError)
        } else if let localizedError = error as? any LocalizedError {
          localizedErrorBody(for: localizedError)
        }
      }
    }
    .padding()
    .frame(maxWidth: 400)
  }
  
  private var errorTitle: String {
    if let decodingError = error as? DecodingError {
      return decodingErrorTitle(for: decodingError)
    } else if let localizedError = error as? any LocalizedError,
       let errorDescription = localizedError.errorDescription {
      return errorDescription
    } else {
      return error.localizedDescription
    }
  }
  
  @ViewBuilder
  private func localizedErrorBody(for error: any LocalizedError) -> some View {
    if let failureReason = error.failureReason {
      VStack(alignment: .leading, spacing: 4) {
        Text("Reason")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(failureReason)
          .font(.body)
          .lineLimit(.max)
          .multilineTextAlignment(.leading)
      }
    }
    
    if let recoverySuggestion = error.recoverySuggestion {
      VStack(alignment: .leading, spacing: 4) {
        Text("Recovery Suggestion")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(recoverySuggestion)
          .font(.body)
          .lineLimit(.max)
          .multilineTextAlignment(.leading)
      }
    }
    
    if let helpAnchor = error.helpAnchor {
      VStack(alignment: .leading, spacing: 4) {
        Text("Help")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(helpAnchor)
          .font(.body)
          .lineLimit(.max)
          .multilineTextAlignment(.leading)
      }
    }
  }
  
  @ViewBuilder
  private func decodingErrorBody(for error: DecodingError) -> some View {
    switch error {
    case .typeMismatch(let type, let context):
      VStack(alignment: .leading, spacing: 8) {
        errorContextView(title: "Type Mismatch", detail: "Expected type: \(type)", context: context)
      }
      
    case .valueNotFound(let type, let context):
      VStack(alignment: .leading, spacing: 8) {
        errorContextView(title: "Value Not Found", detail: "Missing value of type: \(type)", context: context)
      }
      
    case .keyNotFound(let key, let context):
      VStack(alignment: .leading, spacing: 8) {
        errorContextView(title: "Key Not Found", detail: "Missing key: '\(key.stringValue)'", context: context)
      }
      
    case .dataCorrupted(let context):
      VStack(alignment: .leading, spacing: 8) {
        errorContextView(title: "Data Corrupted", detail: nil, context: context)
      }
      
    @unknown default:
      Text("Unknown decoding error")
        .font(.body)
        .foregroundColor(.secondary)
    }
  }
  
  @ViewBuilder
  private func errorContextView(title: String, detail: String?, context: DecodingError.Context) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)
      
      if let detail = detail {
        Text(detail)
          .font(.body)
          .lineLimit(.max)
          .multilineTextAlignment(.leading)
      }
    }
    
    if !context.debugDescription.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("Description")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(context.debugDescription)
          .font(.body)
          .lineLimit(.max)
          .multilineTextAlignment(.leading)
      }
    }
    
    if !context.codingPath.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("Path")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(formatCodingPath(context.codingPath))
          .font(.body)
          .lineLimit(.max)
          .multilineTextAlignment(.leading)
      }
    }
  }
  
  private func formatCodingPath(_ path: [any CodingKey]) -> String {
    path.map { key in
      if let intValue = key.intValue {
        return "[\(intValue)]"
      } else {
        return key.stringValue
      }
    }.joined(separator: " → ")
  }
  
  private func decodingErrorTitle(for error: DecodingError) -> String {
    switch error {
    case .typeMismatch:
      return "JSON Type Mismatch"
    case .valueNotFound:
      return "JSON Value Not Found"
    case .keyNotFound:
      return "JSON Key Not Found"
    case .dataCorrupted:
      return "JSON Data Corrupted"
    @unknown default:
      return "JSON Decoding Error"
    }
  }
}

// Preview
struct ErrorDetailView_Previews: PreviewProvider {
  enum PreviewError: LocalizedError {
    case sample
    
    var errorDescription: String? {
      "Invalid JSON Format"
    }
    
    var failureReason: String? {
      "The JSON contains a syntax error on line 5"
    }
    
    var recoverySuggestion: String? {
      "Check for missing commas, brackets, or quotes"
    }
    
    var helpAnchor: String? {
      "json-syntax-help"
    }
  }
  
  static var previews: some View {
    ErrorDetailView(error: PreviewError.sample)
      .previewLayout(.sizeThatFits)
  }
}
