// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import AppKit

enum TerminalApp: String, CaseIterable, Identifiable {
  case terminal = "com.apple.Terminal"
  case iterm = "com.googlecode.iterm2"
  case ghostty = "com.mitchellh.ghostty"
  
  var id: String { rawValue }
  
  var name: String {
    switch self {
    case .terminal: return "Terminal"
    case .iterm: return "iTerm"
    case .ghostty: return "Ghostty"
    }
  }
  
  var isInstalled: Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil
  }
  
  var icon: NSImage {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) else {
      return NSImage()
    }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
  
  func readShellPath() -> String? {
    switch self {
    case .terminal:
      return readTerminalShell()
    case .iterm:
      return readITermShell()
    case .ghostty:
      return readGhosttyShell()
    }
  }
  
  private func readTerminalShell() -> String? {
    let plistPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Preferences/com.apple.Terminal.plist")
    
    guard let plistData = try? Data(contentsOf: plistPath),
          let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
          let shell = plist["Shell"] as? String else {
      return nil
    }
    
    return shell
  }
  
  private func readITermShell() -> String? {
    let plistPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Preferences/com.googlecode.iterm2.plist")
    
    guard let plistData = try? Data(contentsOf: plistPath),
          let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
          let bookmarks = plist["New Bookmarks"] as? [[String: Any]] else {
      return nil
    }
    
    for bookmark in bookmarks {
      if let command = bookmark["Command"] as? String {
        return command
      }
    }
    
    return nil
  }
  
  private func readGhosttyShell() -> String? {
    let configPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/com.mitchellh.ghostty/config")
    
    guard let configContent = try? String(contentsOf: configPath, encoding: .utf8) else {
      return nil
    }
    
    for line in configContent.split(separator: "\n") {
      let trimmedLine = line.trimmingCharacters(in: .whitespaces)
      
      if trimmedLine.hasPrefix("#") || trimmedLine.isEmpty {
        continue
      }
      
      if let equalIndex = trimmedLine.firstIndex(of: "=") {
        let key = trimmedLine[..<equalIndex].trimmingCharacters(in: .whitespaces)
        let value = trimmedLine[trimmedLine.index(after: equalIndex)...].trimmingCharacters(in: .whitespaces)
        
        if key == "command" && !value.isEmpty {
          return value
        }
      }
    }
    
    return nil
  }
}