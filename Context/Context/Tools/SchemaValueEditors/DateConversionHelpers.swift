// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

enum DateConversionHelpers {
  static func parseDate(from string: String, format: String) -> Date? {
    switch format {
    case "date":
      // ISO 8601 date format: YYYY-MM-DD
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      return formatter.date(from: string)
      
    case "time":
      // ISO 8601 time format: HH:MM:SS
      // Parse time and combine with today's date
      let formatter = DateFormatter()
      formatter.dateFormat = "HH:mm:ss"
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      
      // Handle optional fractional seconds and timezone
      var timeString = string
      if let tIndex = timeString.firstIndex(of: "T") {
        timeString = String(timeString[timeString.index(after: tIndex)...])
      }
      
      // Remove timezone suffix for parsing
      if let zIndex = timeString.firstIndex(of: "Z") {
        timeString = String(timeString[..<zIndex])
      } else if let plusIndex = timeString.firstIndex(of: "+") {
        timeString = String(timeString[..<plusIndex])
      } else if let minusIndex = timeString.lastIndex(of: "-"),
                minusIndex > timeString.index(timeString.startIndex, offsetBy: 2) {
        timeString = String(timeString[..<minusIndex])
      }
      
      // Remove fractional seconds for parsing
      if let dotIndex = timeString.firstIndex(of: ".") {
        timeString = String(timeString[..<dotIndex])
      }
      
      return formatter.date(from: timeString)
      
    case "date-time":
      // ISO 8601 date-time format
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      
      // Try with fractional seconds first
      formatter.formatOptions.insert(.withFractionalSeconds)
      if let date = formatter.date(from: string) {
        return date
      }
      
      // Try without fractional seconds
      formatter.formatOptions.remove(.withFractionalSeconds)
      return formatter.date(from: string)
      
    default:
      return nil
    }
  }
  
  static func formatDate(_ date: Date, format: String) -> String {
    switch format {
    case "date":
      // ISO 8601 date format: YYYY-MM-DD
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      return formatter.string(from: date)
      
    case "time":
      // ISO 8601 time format: HH:MM:SS
      let formatter = DateFormatter()
      formatter.dateFormat = "HH:mm:ss"
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      return formatter.string(from: date)
      
    case "date-time":
      // ISO 8601 date-time format
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      return formatter.string(from: date)
      
    default:
      return ""
    }
  }
}