// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import Foundation
import SwiftUI

enum ColorConversionHelpers {
  static func colorFromString(_ colorStr: String) -> Color? {
    let trimmed = colorStr.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Handle hex colors (with or without #)
    if trimmed.hasPrefix("#") || trimmed.range(of: "^[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$", options: .regularExpression) != nil {
      let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
      
      // Convert hex to RGB
      guard hex.count == 6 || hex.count == 8 else { return nil }
      
      let scanner = Scanner(string: hex)
      var rgbValue: UInt64 = 0
      scanner.scanHexInt64(&rgbValue)
      
      if hex.count == 6 {
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
      } else {
        let r = Double((rgbValue & 0xFF000000) >> 24) / 255.0
        let g = Double((rgbValue & 0x00FF0000) >> 16) / 255.0
        let b = Double((rgbValue & 0x0000FF00) >> 8) / 255.0
        let a = Double(rgbValue & 0x000000FF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
      }
    }
    
    // Handle rgb/rgba colors
    if trimmed.hasPrefix("rgb") {
      let pattern = "rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([0-9.]+))?\\)"
      guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
        return nil
      }
      
      func extractValue(at index: Int) -> Double? {
        guard let range = Range(match.range(at: index), in: trimmed) else { return nil }
        return Double(trimmed[range])
      }
      
      guard let r = extractValue(at: 1),
            let g = extractValue(at: 2),
            let b = extractValue(at: 3) else {
        return nil
      }
      
      let a = extractValue(at: 4) ?? 1.0
      
      return Color(red: r / 255.0, green: g / 255.0, blue: b / 255.0, opacity: a)
    }
    
    // Handle named colors
    switch trimmed.lowercased() {
    case "red": return .red
    case "green": return .green
    case "blue": return .blue
    case "yellow": return .yellow
    case "orange": return .orange
    case "purple": return .purple
    case "pink": return .pink
    case "gray", "grey": return .gray
    case "black": return .black
    case "white": return .white
    case "clear", "transparent": return .clear
    default: return nil
    }
  }
  
  static func colorToHexString(_ color: Color) -> String {
    // Convert SwiftUI Color to NSColor
    let nsColor = NSColor(color)
    
    // Get RGB components
    guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
      return "#000000"
    }
    
    let r = Int(rgbColor.redComponent * 255)
    let g = Int(rgbColor.greenComponent * 255)
    let b = Int(rgbColor.blueComponent * 255)
    let a = Int(rgbColor.alphaComponent * 255)
    
    // Return hex with alpha only if not fully opaque
    if a < 255 {
      return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    } else {
      return String(format: "#%02X%02X%02X", r, g, b)
    }
  }
}