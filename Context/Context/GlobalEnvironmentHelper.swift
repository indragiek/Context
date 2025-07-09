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

    var environment: [String: String] = [:]
    for variable in variables {
      environment[variable.key] = variable.value
    }

    // Perform variable substitution using the login shell
    return try await expandEnvironmentVariables(environment)
  }

  /// Perform variable substitution using the user's login shell
  private static func expandEnvironmentVariables(_ environment: [String: String]) async throws -> [String:
    String]
  {
    guard !environment.isEmpty else { return [:] }

    var expandedEnvironment: [String: String] = [:]

    for (key, value) in environment {
      let expandedValue = try await expandVariableValue(value)
      expandedEnvironment[key] = expandedValue
    }

    return expandedEnvironment
  }

  /// Expand a single environment variable value using the login shell
  private static func expandVariableValue(_ value: String) async throws -> String {
    // If the value doesn't contain any $ symbols, no expansion is needed
    guard value.contains("$") else { return value }

    let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

    // Create a temporary script that will echo the expanded value
    let script = """
      echo "\(value.replacingOccurrences(of: "\"", with: "\\\""))"
      """

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
      return value  // If expansion fails, return original value
    }

    // Trim whitespace and newlines
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

