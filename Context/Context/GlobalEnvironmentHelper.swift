// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Dependencies
import Foundation
import SharingGRDB

/// Helper to manage global environment variables with variable substitution
struct GlobalEnvironmentHelper {
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

  /// Perform variable substitution using the user's login shell
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

  /// Expand a single environment variable value using the login shell
  private static func expandVariableValue(_ value: String) async throws -> String {
    guard value.contains("$") else { return value }

    let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
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
