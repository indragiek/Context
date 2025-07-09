// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation
import RegexBuilder

/// Processes template variables in prompt content
struct TemplateProcessor {
  // Cached regex for template matching
  @MainActor
  private static let templateVarRegex = /\{\{([^}]+)\}\}/
  @MainActor
  private static let conditionalRegex = /\{\{([#^])([^}]+)\}\}(.*?)\{\{\/\2\}\}/
  
  private let argumentValues: [String: String]
  private let maxIterations = 10
  
  init(argumentValues: [String: String]) {
    self.argumentValues = argumentValues
  }
  
  @MainActor
  func process(_ content: Content) -> Content {
    switch content {
    case .text(let text, let annotations):
      return .text(processText(text), annotations: annotations)
      
    case .resource(let embeddedResource, let annotations):
      return .resource(processResource(embeddedResource), annotations: annotations)
      
    default:
      return content
    }
  }
  
  @MainActor
  private func processText(_ text: String) -> String {
    var processedText = text
    var iterationCount = 0
    
    // Replace simple template variables {{key}} with actual values
    processedText = processedText.replacing(Self.templateVarRegex) { match in
      iterationCount += 1
      guard iterationCount < maxIterations else {
        return String(match.output.0)
      }
      
      let key = String(match.output.1).trimmingCharacters(in: .whitespaces)
      if let value = argumentValues[key], !value.isEmpty {
        return value
      }
      return String(match.output.0)
    }
    
    // Handle conditional sections {{#key}}...{{/key}} and {{^key}}...{{/key}}
    iterationCount = 0
    processedText = processedText.replacing(Self.conditionalRegex) { match in
      iterationCount += 1
      guard iterationCount < maxIterations else {
        // Too many replacements, likely malformed template
        return String(match.output.0)
      }
      
      let conditionType = String(match.output.1)  // "#" or "^"
      let key = String(match.output.2).trimmingCharacters(in: .whitespaces)
      let content = String(match.output.3)
      
      let hasValue = argumentValues[key]
        .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        ?? false
      
      if conditionType == "#" {
        return hasValue ? content : ""
      } else {
        return hasValue ? "" : content
      }
    }
    
    return processedText
  }
  
  @MainActor
  private func processResource(_ resource: EmbeddedResource) -> EmbeddedResource {
    switch resource {
    case .text(let textResource):
      let processedURI = processText(textResource.uri)
      let processedText = processText(textResource.text)
      
      return .text(
        TextResourceContents(
          uri: processedURI,
          mimeType: textResource.mimeType,
          text: processedText
        )
      )
      
    case .blob(let blobResource):
      let processedURI = processText(blobResource.uri)
      
      return .blob(
        BlobResourceContents(
          uri: processedURI,
          mimeType: blobResource.mimeType,
          blob: blobResource.blob
        )
      )
    }
  }
}