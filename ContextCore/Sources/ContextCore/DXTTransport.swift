// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import os

/// Errors thrown by `DXTTransport`
public enum DXTTransportError: Error, LocalizedError {
  /// The DXT directory could not be found at the specified path
  case dxtDirectoryNotFound(URL)
  
  /// The manifest.json file is missing from the DXT directory
  case missingManifest
  
  /// The manifest.json file could not be decoded
  case invalidManifest(Error)
  
  /// The current platform (darwin) is not supported by the extension
  case unsupportedPlatform(supported: [String])
  
  /// The required runtime is not installed
  case runtimeNotInstalled(runtime: String)
  
  /// The installed runtime version does not meet the requirements
  case runtimeVersionMismatch(runtime: String, required: String, installed: String)
  
  /// The server entry point is missing from the DXT archive
  case missingEntryPoint(String)
  
  /// The user configuration value is required but not provided
  case missingRequiredConfig(key: String)
  
  /// The Context app version does not meet the requirements
  case contextVersionMismatch(required: String, installed: String)
  
  /// The user configuration contains sensitive values that should be stored as keychain references
  case sensitiveValuesNotInKeychain
  
  /// The user configuration value is out of the allowed range
  case configValueOutOfRange(key: String, message: String)
  
  /// The binary is not executable
  case binaryNotExecutable(name: String)
  
  /// The binary path escapes the DXT directory through symlinks
  case binaryPathEscape
  
  /// The entry point contains path traversal attempts
  case pathTraversal(path: String)
  
  public var errorDescription: String? {
    switch self {
    case .dxtDirectoryNotFound(let url):
      return "DXT directory not found at \(url.path)"
    case .missingManifest:
      return "manifest.json not found in DXT directory"
    case .invalidManifest(let error):
      return "Invalid manifest.json: \(error.localizedDescription)"
    case .unsupportedPlatform(let supported):
      return "Platform 'darwin' not supported. Supported platforms: \(supported.joined(separator: ", "))"
    case .runtimeNotInstalled(let runtime):
      return "\(runtime) is not installed"
    case .runtimeVersionMismatch(let runtime, let required, let installed):
      return "\(runtime) version \(installed) does not meet requirement: \(required)"
    case .missingEntryPoint(let path):
      return "Server entry point not found: \(path)"
    case .missingRequiredConfig(let key):
      return "Required user configuration missing: \(key)"
    case .contextVersionMismatch(let required, let installed):
      return "Context version \(installed) does not meet requirement: \(required)"
    case .sensitiveValuesNotInKeychain:
      return "User configuration contains sensitive values that should be stored as keychain references"
    case .configValueOutOfRange(let key, let message):
      return "Configuration value '\(key)': \(message)"
    case .binaryNotExecutable(let name):
      return "Binary '\(name)' is not executable"
    case .binaryPathEscape:
      return "Binary path escapes DXT directory through symlinks"
    case .pathTraversal(let path):
      return "Entry point contains path traversal: \(path)"
    }
  }
}

extension DXTTransportError: Equatable {
  public static func == (lhs: DXTTransportError, rhs: DXTTransportError) -> Bool {
    switch (lhs, rhs) {
    case let (.dxtDirectoryNotFound(url1), .dxtDirectoryNotFound(url2)):
      return url1 == url2
    case (.missingManifest, .missingManifest):
      return true
    case let (.invalidManifest(error1), .invalidManifest(error2)):
      // Compare error descriptions since Error doesn't conform to Equatable
      return String(describing: error1) == String(describing: error2)
    case let (.unsupportedPlatform(supported1), .unsupportedPlatform(supported2)):
      return supported1 == supported2
    case let (.runtimeNotInstalled(runtime1), .runtimeNotInstalled(runtime2)):
      return runtime1 == runtime2
    case let (.runtimeVersionMismatch(runtime1, required1, installed1),
              .runtimeVersionMismatch(runtime2, required2, installed2)):
      return runtime1 == runtime2 && required1 == required2 && installed1 == installed2
    case let (.missingEntryPoint(path1), .missingEntryPoint(path2)):
      return path1 == path2
    case let (.missingRequiredConfig(key1), .missingRequiredConfig(key2)):
      return key1 == key2
    case let (.contextVersionMismatch(required1, installed1),
              .contextVersionMismatch(required2, installed2)):
      return required1 == required2 && installed1 == installed2
    case (.sensitiveValuesNotInKeychain, .sensitiveValuesNotInKeychain):
      return true
    case let (.configValueOutOfRange(key1, message1), .configValueOutOfRange(key2, message2)):
      return key1 == key2 && message1 == message2
    case let (.binaryNotExecutable(name1), .binaryNotExecutable(name2)):
      return name1 == name2
    case (.binaryPathEscape, .binaryPathEscape):
      return true
    case let (.pathTraversal(path1), .pathTraversal(path2)):
      return path1 == path2
    default:
      return false
    }
  }
}

/// Transport implementation that wraps StdioTransport for DXT packages
public actor DXTTransport: Transport {
  private let stdioTransport: StdioTransport
  /// The parsed DXT manifest
  public let manifest: DXTManifest
  private let dxtDirectory: URL
  private let logger = Logger(subsystem: "com.indragie.ContextCore", category: "DXTTransport")
  
  // Cached regex for placeholder validation
  private static let placeholderRegex = /\$\{[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*\}/
  
  /// Initializes a DXTTransport with the specified extracted DXT directory
  /// - Parameters:
  ///   - dxtDirectory: URL to the extracted DXT directory containing manifest.json
  ///   - clientInfo: Client implementation information
  ///   - clientCapabilities: Client capabilities
  ///   - userConfig: User configuration values
  public init(
    dxtDirectory: URL,
    clientInfo: Implementation,
    clientCapabilities: ClientCapabilities,
    userConfig: DXTUserConfigurationValues? = nil
  ) async throws {
    // Verify the directory exists
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dxtDirectory.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      throw DXTTransportError.dxtDirectoryNotFound(dxtDirectory)
    }
    
    self.dxtDirectory = dxtDirectory
    
    // Load and parse manifest
    let manifestURL = dxtDirectory.appendingPathComponent("manifest.json")
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw DXTTransportError.missingManifest
    }
    
    let manifestData = try Data(contentsOf: manifestURL)
    let parsedManifest: DXTManifest
    do {
      parsedManifest = try JSONDecoder().decode(DXTManifest.self, from: manifestData)
    } catch {
      throw DXTTransportError.invalidManifest(error)
    }
    self.manifest = parsedManifest
    
    // Validate compatibility
    try Self.validateCompatibility(manifest: parsedManifest)
    
    // Check if user config contains sensitive values (not allowed)
    if let config = userConfig, config.containsSensitiveValues {
      throw DXTTransportError.sensitiveValuesNotInKeychain
    }
    
    // Check for missing required config
    if let config = userConfig {
      let missingKeys = config.missingRequiredKeys(from: parsedManifest)
      if let firstMissing = missingKeys.first {
        throw DXTTransportError.missingRequiredConfig(key: firstMissing)
      }
      
      // Validate number ranges
      let rangeErrors = config.validateNumberRanges(from: parsedManifest)
      if let firstError = rangeErrors.first {
        // Extract key from error message (format: "key: message")
        let components = firstError.split(separator: ":", maxSplits: 1)
        let key = components.first.map(String.init) ?? "unknown"
        let message = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespaces) : firstError
        throw DXTTransportError.configValueOutOfRange(key: key, message: message)
      }
      
      // Validate file and directory paths
      let pathErrors = config.validatePaths(from: parsedManifest)
      if let firstError = pathErrors.first {
        // Extract key from error message (format: "key: message")
        let components = firstError.split(separator: ":", maxSplits: 1)
        let key = components.first.map(String.init) ?? "unknown"
        let message = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespaces) : firstError
        throw DXTTransportError.configValueOutOfRange(key: key, message: message)
      }
    } else if let userConfigDef = parsedManifest.userConfig,
              userConfigDef.contains(where: { $0.value.required == true }) {
      // Has required config but no config provided
      if let firstRequired = userConfigDef.first(where: { $0.value.required == true }) {
        throw DXTTransportError.missingRequiredConfig(key: firstRequired.key)
      }
    }
    
    // Validate entry point for path traversal attempts
    let entryPoint = parsedManifest.server.entryPoint
    if entryPoint.contains("..") || entryPoint.hasPrefix("/") || entryPoint.hasPrefix("~") {
      throw DXTTransportError.pathTraversal(path: entryPoint)
    }
    
    // Verify entry point exists
    let entryPointURL = dxtDirectory.appendingPathComponent(entryPoint)
    guard FileManager.default.fileExists(atPath: entryPointURL.path) else {
      throw DXTTransportError.missingEntryPoint(entryPoint)
    }
    
    // Additional security validation for binary server types
    if parsedManifest.server.type == .binary {
      try Self.validateBinaryExecutable(at: entryPointURL)
    }
    
    // Build server process info
    let processInfo = try Self.buildProcessInfo(
      manifest: parsedManifest,
      dxtDirectory: dxtDirectory,
      userConfig: userConfig
    )
    
    // Initialize stdio transport
    self.stdioTransport = StdioTransport(
      serverProcessInfo: processInfo,
      clientInfo: clientInfo,
      clientCapabilities: clientCapabilities
    )
  }
  
  /// Validates the compatibility requirements specified in a DXT manifest
  /// - Parameter manifest: The DXT manifest to validate
  /// - Throws: DXTTransportError if any compatibility requirements are not met
  public static func validateManifestCompatibility(_ manifest: DXTManifest) throws {
    try validateCompatibility(manifest: manifest)
  }
  
  // MARK: - Transport Protocol Implementation
  
  public typealias ResponseSequence = StdioTransport.ResponseSequence
  public typealias LogSequence = StdioTransport.LogSequence
  public typealias ConnectionStateSequence = StdioTransport.ConnectionStateSequence
  
  public func start() async throws {
    try await stdioTransport.start()
  }
  
  public func initialize(idGenerator: @escaping IDGenerator) async throws -> InitializeResponse.Result {
    try await stdioTransport.initialize(idGenerator: idGenerator)
  }
  
  public func send(request: any JSONRPCRequest) async throws {
    try await stdioTransport.send(request: request)
  }
  
  public func send(notification: any JSONRPCNotification) async throws {
    try await stdioTransport.send(notification: notification)
  }
  
  public func send(response: any JSONRPCResponse) async throws {
    try await stdioTransport.send(response: response)
  }
  
  public func send(error: JSONRPCError) async throws {
    try await stdioTransport.send(error: error)
  }
  
  public func send(batch: [JSONRPCBatchItem]) async throws {
    try await stdioTransport.send(batch: batch)
  }
  
  public func receive() async throws -> ResponseSequence {
    try await stdioTransport.receive()
  }
  
  public func receiveLogs() async throws -> LogSequence {
    try await stdioTransport.receiveLogs()
  }
  
  public func receiveConnectionState() async throws -> ConnectionStateSequence {
    try await stdioTransport.receiveConnectionState()
  }
  
  public func close() async throws {
    try await stdioTransport.close()
  }
  
  // MARK: - Private Methods
  
  private static func validateCompatibility(manifest: DXTManifest) throws {
    guard let compatibility = manifest.compatibility else {
      // No compatibility checks needed
      return
    }
    
    // Check platform compatibility
    if let platforms = compatibility.platforms {
      guard platforms.contains("darwin") else {
        throw DXTTransportError.unsupportedPlatform(supported: platforms)
      }
    }
    
    // Check runtime versions
    if let runtimes = compatibility.runtimes {
      for (runtime, requirement) in runtimes {
        switch runtime {
        case "python":
          try validatePythonVersion(requirement: requirement)
        case "node":
          try validateNodeVersion(requirement: requirement)
        default:
          // Unknown runtime requirement - skip validation
          break
        }
      }
    }
    
    // Check Context app version
    if let contextRequirement = compatibility.context {
      try validateContextVersion(requirement: contextRequirement)
    }
  }
  
  private static func validatePythonVersion(requirement: String) throws {
    // Try "python" first, then fallback to "python3"
    let commands = ["python", "python3"]
    var lastError: Error?
    
    for command in commands {
      do {
        let result = try runCommand(command, args: ["--version"])
        guard let output = result.output else {
          continue
        }
        
        // Parse version from "Python 3.x.x"
        let components = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        guard components.count >= 2 else {
          continue
        }
        
        let versionString = components[1]
        guard let version = SemanticVersion(string: versionString) else {
          continue
        }
        
        guard version.satisfies(requirement) else {
          throw DXTTransportError.runtimeVersionMismatch(
            runtime: "python",
            required: requirement,
            installed: versionString
          )
        }
        
        // Version check passed
        return
      } catch {
        lastError = error
        // Continue to try next command
      }
    }
    
    // If we get here, none of the commands worked
    if let error = lastError as? DXTTransportError {
      throw error
    } else {
      throw DXTTransportError.runtimeNotInstalled(runtime: "python")
    }
  }
  
  private static func validateContextVersion(requirement: String) throws {
    // Get the app's bundle
    let bundle = Bundle.main
    guard let versionString = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
      // If we can't determine the version, we could be running in tests or a different context
      // In production, Context app should always have a version
      return
    }
    
    guard let version = SemanticVersion(string: versionString) else {
      throw DXTTransportError.contextVersionMismatch(
        required: requirement,
        installed: versionString
      )
    }
    
    guard version.satisfies(requirement) else {
      throw DXTTransportError.contextVersionMismatch(
        required: requirement,
        installed: versionString
      )
    }
  }
  
  private static func validateNodeVersion(requirement: String) throws {
    let result = try runCommand("node", args: ["--version"])
    guard let output = result.output else {
      throw DXTTransportError.runtimeNotInstalled(runtime: "node")
    }
    
    // Parse version from "v16.x.x"
    let versionString = output.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    
    guard let version = SemanticVersion(string: versionString) else {
      throw DXTTransportError.runtimeNotInstalled(runtime: "node")
    }
    
    guard version.satisfies(requirement) else {
      throw DXTTransportError.runtimeVersionMismatch(
        runtime: "node",
        required: requirement,
        installed: versionString
      )
    }
  }
  
  /// Validates that a binary is safe to execute
  private static func validateBinaryExecutable(at url: URL) throws {
    let fileManager = FileManager.default
    
    // Check if file is executable
    guard fileManager.isExecutableFile(atPath: url.path) else {
      throw DXTTransportError.binaryNotExecutable(name: url.lastPathComponent)
    }
    
    // Check that the binary is within the DXT directory (no symlinks escaping)
    let realPath = url.resolvingSymlinksInPath()
    let dxtRealPath = url.deletingLastPathComponent().resolvingSymlinksInPath()
    
    guard realPath.path.hasPrefix(dxtRealPath.path) else {
      throw DXTTransportError.binaryPathEscape
    }
  }
  
  /// Apply substitutions safely, tracking circular references
  private static func applySubstitutions(_ input: String, substitutions: [String: String], visited: Set<String> = []) -> String {
    var result = input
    var visitedKeys = visited
    
    // Apply each substitution, checking for circular references
    for (pattern, replacement) in substitutions {
      guard !visitedKeys.contains(pattern) else {
        // Circular reference detected - skip this substitution
        continue
      }
      
      if result.contains(pattern) {
        // Add to visited set to detect circular references
        visitedKeys.insert(pattern)
        
        // Recursively apply substitutions to the replacement value
        let processedReplacement = applySubstitutions(replacement, substitutions: substitutions, visited: visitedKeys)
        result = result.replacingOccurrences(of: pattern, with: processedReplacement)
      }
    }
    
    return result
  }
  
  /// Check if a string contains unresolved placeholders
  private static func containsUnresolvedPlaceholders(_ input: String) -> Bool {
    return input.contains(placeholderRegex)
  }
  
  private static func runCommand(_ command: String, args: [String]) throws -> (output: String?, error: String?) {
    let task = Process()
    
    // Use the user's shell to run commands
    let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    var shellArgs = ["-l", "-c"]
    
    // Build command string with escaped arguments
    var commandString = command
    if !args.isEmpty {
      let escapedArgs = args.map { arg in
        "'" + arg.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
      }.joined(separator: " ")
      commandString += " " + escapedArgs
    }
    shellArgs.append(commandString)
    
    task.executableURL = URL(fileURLWithPath: shellPath)
    task.arguments = shellArgs
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = errorPipe
    
    do {
      try task.run()
      task.waitUntilExit()
      
      let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      
      // Check if command failed with "command not found"
      if task.terminationStatus == 127 {
        throw DXTTransportError.runtimeNotInstalled(runtime: command)
      }
      
      return (
        output: String(data: outputData, encoding: .utf8),
        error: String(data: errorData, encoding: .utf8)
      )
    } catch {
      // Clean up pipes on error
      try? outputPipe.fileHandleForReading.close()
      try? errorPipe.fileHandleForReading.close()
      throw DXTTransportError.runtimeNotInstalled(runtime: command)
    }
  }
  
  
  static func buildProcessInfo(
    manifest: DXTManifest,
    dxtDirectory: URL,
    userConfig: DXTUserConfigurationValues?
  ) throws -> StdioTransport.ServerProcessInfo {
    
    // Start with base MCP config
    var command = manifest.server.mcpConfig.command
    var args = manifest.server.mcpConfig.args ?? []
    var env = manifest.server.mcpConfig.env ?? [:]
    
    // Apply platform overrides if present
    if let platformOverrides = manifest.compatibility?.platformOverrides {
      // Only apply overrides for the current platform (darwin)
      if let darwinOverrides = platformOverrides["darwin"] {
        if let overrideCommand = darwinOverrides.command {
          command = overrideCommand
        }
        if let overrideArgs = darwinOverrides.args {
          args = overrideArgs
        }
        if let overrideEnv = darwinOverrides.env {
          env.merge(overrideEnv) { _, new in new }
        }
      }
      // Explicitly ignore overrides for other platforms
    }
    
    
    // Apply compatibility environment variables
    if let compatEnv = manifest.compatibility?.env {
      env.merge(compatEnv) { _, new in new }
    }
    
    // Build substitution context
    var substitutions: [String: String] = [:]
    
    // Add __dirname substitution
    substitutions["${__dirname}"] = dxtDirectory.path
    
    // Add user config substitutions
    if let userConfig = userConfig {
      for (key, configValue) in userConfig.values {
        let substituteKey = "${user_config.\(key)}"
        switch configValue.value {
        case .string(let value):
          substitutions[substituteKey] = value
        case .number(let value):
          substitutions[substituteKey] = String(value)
        case .boolean(let value):
          substitutions[substituteKey] = String(value)
        case .stringArray(_):
          // Arrays will be handled specially in args substitution
          continue
        case .keychainReference:
          // Should not happen - these should be resolved before DXTTransport init
          continue
        }
      }
    }
    
    // Add environment variable substitutions
    let fm = FileManager.default
    
    // HOME directory
    if let home = ProcessInfo.processInfo.environment["HOME"] {
      substitutions["${HOME}"] = home
    } else if let home = fm.homeDirectoryForCurrentUser.path as String? {
      substitutions["${HOME}"] = home
    }
    
    // Platform-specific directories
    // DESKTOP
    if let desktopPath = try? fm.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path {
      substitutions["${DESKTOP}"] = desktopPath
    }
    
    // DOCUMENTS
    if let documentsPath = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path {
      substitutions["${DOCUMENTS}"] = documentsPath
    }
    
    // DOWNLOADS
    if let downloadsPath = try? fm.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path {
      substitutions["${DOWNLOADS}"] = downloadsPath
    }
    
    // Path separator
    #if os(Windows)
    substitutions["${pathSeparator}"] = "\\"
    substitutions["${/}"] = "\\"
    #else
    substitutions["${pathSeparator}"] = "/"
    substitutions["${/}"] = "/"
    #endif
    
    // Apply substitutions to args with array expansion
    var expandedArgs: [String] = []
    for arg in args {
      // Check if this arg is a user_config array substitution
      var arrayExpanded = false
      if let userConfig = userConfig {
        for (key, configValue) in userConfig.values {
          let substituteKey = "${user_config.\(key)}"
          if arg == substituteKey {
            // Handle array expansion for exact matches
            if case .stringArray(let values) = configValue.value {
              expandedArgs.append(contentsOf: values)
              arrayExpanded = true
              break
            }
          }
        }
      }
      
      if !arrayExpanded {
        // Apply regular substitutions with circular reference protection
        let result = applySubstitutions(arg, substitutions: substitutions)
        // Skip arguments that still contain unresolved placeholders
        if !containsUnresolvedPlaceholders(result) {
          expandedArgs.append(result)
        }
      }
    }
    args = expandedArgs
    
    // Apply substitutions to env
    var processedEnv: [String: String] = [:]
    for (key, value) in env {
      var result = value
      
      // First check if this env var contains an array substitution
      if let userConfig = userConfig {
        for (configKey, configValue) in userConfig.values {
          let substituteKey = "${user_config.\(configKey)}"
          if value.contains(substituteKey) {
            if case .stringArray(let values) = configValue.value {
              // For environment variables, join array values with PATH separator
              let separator = configValue.configType == "directory" || configValue.configType == "file" ? ":" : ","
              let joinedValue = values.joined(separator: separator)
              result = result.replacingOccurrences(of: substituteKey, with: joinedValue)
            }
          }
        }
      }
      
      // Apply regular substitutions with circular reference protection
      result = applySubstitutions(result, substitutions: substitutions)
      // Skip environment variables that still contain unresolved placeholders
      if !containsUnresolvedPlaceholders(result) {
        processedEnv[key] = result
      }
    }
    env = processedEnv
    
    // Apply substitutions to command with circular reference protection
    command = applySubstitutions(command, substitutions: substitutions)
    
    // Get shell path from environment
    let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    var shellArgs = ["-l", "-c"]
    
    // Build command string
    var commandString = command
    if !args.isEmpty {
      let escapedArgs = args.map { arg in
        "'" + arg.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
      }.joined(separator: " ")
      commandString += " " + escapedArgs
    }
    shellArgs.append(commandString)
    
    // Set working directory
    let workingDirectory = manifest.server.mcpConfig.workingDirectory.map { dir in
      var result = dir
      for (pattern, replacement) in substitutions {
        result = result.replacingOccurrences(of: pattern, with: replacement)
      }
      return URL(fileURLWithPath: result)
    }
    
    return StdioTransport.ServerProcessInfo(
      executableURL: URL(fileURLWithPath: shellPath),
      arguments: shellArgs,
      environment: env,
      currentDirectoryURL: workingDirectory ?? dxtDirectory
    )
  }
}