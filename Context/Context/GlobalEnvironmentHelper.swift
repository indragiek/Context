// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Dependencies
import Foundation
import SharingGRDB

enum ShellPathError: LocalizedError {
  case doesNotExist(String)
  case notExecutable(String)
  
  var errorDescription: String? {
    switch self {
    case .doesNotExist(let path):
      return "Shell path does not exist: \(path)"
    case .notExecutable(let path):
      return "Shell path is not executable: \(path)"
    }
  }
}

/// Helper to manage global environment variables with variable substitution
struct GlobalEnvironmentHelper {
  private static let shellPathKey = "customShellPath"
  
  /// Read the shell path from UserDefaults or return the default shell
  static func readShellPath() -> String {
    if let customPath = UserDefaults.standard.string(forKey: shellPathKey),
       FileManager.default.isExecutableFile(atPath: customPath) {
      return customPath
    } else if let storedPath = UserDefaults.standard.string(forKey: shellPathKey) {
      // Path exists but is not valid
      print("Warning: Stored shell path '\(storedPath)' is not executable, using default shell")
    }
    return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
  }
  
  /// Write a custom shell path to UserDefaults, or remove it to use default
  static func writeShellPath(_ path: String?) throws {
    if let path = path {
      // Validate the path exists and is executable
      guard FileManager.default.fileExists(atPath: path) else {
        throw ShellPathError.doesNotExist(path)
      }
      guard FileManager.default.isExecutableFile(atPath: path) else {
        throw ShellPathError.notExecutable(path)
      }
      UserDefaults.standard.set(path, forKey: shellPathKey)
    } else {
      // Remove the key to represent default shell selection
      UserDefaults.standard.removeObject(forKey: shellPathKey)
    }
  }
  
  /// Check if using custom shell (returns true if custom path is set)
  static func isUsingCustomShell() -> Bool {
    UserDefaults.standard.string(forKey: shellPathKey) != nil
  }
  
  /// Read global environment variables from the database and perform variable substitution
  static func loadEnvironment() async throws -> [String: String] {
    @Dependency(\.defaultDatabase) var database
    
    let variables = try await database.read { db in
      try GlobalEnvironmentVariable.all.fetchAll(db)
    }

    let environment = Dictionary(
      uniqueKeysWithValues: variables.map { ($0.key, $0.value) }
    )

    return try await expandEnvironmentVariables(environment)
  }

  /// Perform variable substitution using the user's configured shell
  private static func expandEnvironmentVariables(_ environment: [String: String]) async throws -> [String: String] {
    guard !environment.isEmpty else { return [:] }

    return try await withThrowingTaskGroup(of: (String, String).self) { group in
      for (key, value) in environment {
        group.addTask {
          let expandedValue = try await expandVariableValue(value)
          return (key, expandedValue)
        }
      }
      
      return try await group.reduce(into: [:]) { dict, pair in
        dict[pair.0] = pair.1
      }
    }
  }

  /// Expand a single environment variable value using the configured shell
  private static func expandVariableValue(_ value: String) async throws -> String {
    guard value.contains("$") else { return value }

    let shellPath = readShellPath()
    let escapedValue = value.replacingOccurrences(of: "\"", with: "\\\"")
    let script = "echo \"\(escapedValue)\""

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shellPath)
    process.arguments = ["-l", "-c", script]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
      return value
    }

    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
