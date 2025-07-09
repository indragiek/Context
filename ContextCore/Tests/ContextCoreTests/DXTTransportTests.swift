// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing
import ZIPFoundation

@testable import ContextCore

/// Errors specific to DXT transport tests
enum DXTTestError: Error {
  case invalidZipArchive
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct DXTTransportTests {
  
  /// Check if a command is available in the system PATH or at UV_PATH
  private func checkCommandAvailable(_ command: String) async -> Bool {
    // First check if UV_PATH is set and points to a valid executable
    if command == "uv", let uvPath = ProcessInfo.processInfo.environment["UV_PATH"] {
      return FileManager.default.isExecutableFile(atPath: uvPath)
    }
    
    // Otherwise check if command is in PATH
    do {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
      process.arguments = [command]
      
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = Pipe()
      
      try process.run()
      process.waitUntilExit()
      
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }
  
  @Test func testLoadPythonDXT() async throws {
    // Check if uv is available before running this test
    let uvAvailable = await checkCommandAvailable("uv")
    try #require(uvAvailable, "uv is not installed - skipping Python DXT test")
    
    let dxtPath = TestFixtures.dxtPath(name: "file-manager-python")
    let extractedPath = try extractDXT(at: dxtPath)
    defer { try? FileManager.default.removeItem(at: extractedPath) }
    
    let transport = try await DXTTransport(
      dxtDirectory: extractedPath,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities
    )
    
    // Start the transport and verify initialization
    try await transport.start()
    let initResult = try await withTimeout(
      5.0,
      timeoutMessage: "Initialize timed out after 5 seconds",
      defaultValue: InitializeResponse.Result(
        protocolVersion: "",
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: "", version: "")
      )
    ) {
      try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    }
    #expect(initResult.protocolVersion == MCPProtocolVersion)
    #expect(initResult.serverInfo.name == "file-manager-python")
    
    // Test tools list functionality
    let testRequest = ListToolsRequest(id: 1, cursor: nil)
    let response = try await withTimeout(
      5.0,
      timeoutMessage: "Tools list request timed out after 5 seconds",
      defaultValue: TransportResponse.failedRequest(
        request: testRequest,
        error: JSONRPCError(
          error: JSONRPCError.ErrorBody(code: -32000, message: "Timeout", data: nil),
          id: testRequest.id
        )
      )
    ) {
      try await transport.testOnly_sendAndWaitForResponse(request: testRequest)
    }
    
    // Verify we get a valid response
    if case .successfulRequest = response {
      // Success
    } else {
      recordErrorsForNonSuccessfulResponse(response)
    }
    
    try await transport.close()
  }
  
  @Test func testLoadNodeDXT() async throws {
    let dxtPath = TestFixtures.dxtPath(name: "hello-world-node")
    let extractedPath = try extractDXT(at: dxtPath)
    defer { try? FileManager.default.removeItem(at: extractedPath) }
    
    let transport = try await DXTTransport(
      dxtDirectory: extractedPath,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities
    )
    
    // Start the transport and verify initialization
    try await transport.start()
    let initResult = try await withTimeout(
      5.0,
      timeoutMessage: "Initialize timed out after 5 seconds",
      defaultValue: InitializeResponse.Result(
        protocolVersion: "",
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: "", version: "")
      )
    ) {
      try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    }
    #expect(initResult.protocolVersion == MCPProtocolVersion)
    #expect(initResult.serverInfo.name == "hello-world-node")
    
    // Test the get_current_time tool
    let toolsRequest = ListToolsRequest(id: 1, cursor: nil)
    let toolsResponse = try await withTimeout(
      5.0,
      timeoutMessage: "Tools list request timed out after 5 seconds",
      defaultValue: TransportResponse.failedRequest(
        request: toolsRequest,
        error: JSONRPCError(
          error: JSONRPCError.ErrorBody(code: -32000, message: "Timeout", data: nil),
          id: toolsRequest.id
        )
      )
    ) {
      try await transport.testOnly_sendAndWaitForResponse(request: toolsRequest)
    }
    
    // Parse the response to verify the tool is available
    if case let .successfulRequest(_, response) = toolsResponse,
       let listToolsResponse = response as? ListToolsResponse {
      let tools = listToolsResponse.result.tools
      #expect(tools.count > 0)
      let firstTool = tools[0]
      #expect(firstTool.name == "get_current_time")
    } else {
      recordErrorsForNonSuccessfulResponse(toolsResponse)
    }
    
    try await transport.close()
  }
  
  @Test func testMissingDXTDirectory() async throws {
    let missingPath = URL(fileURLWithPath: "/nonexistent/directory")
    
    await #expect(throws: DXTTransportError.dxtDirectoryNotFound(missingPath)) {
      _ = try await DXTTransport(
        dxtDirectory: missingPath,
        clientInfo: TestFixtures.clientInfo,
        clientCapabilities: TestFixtures.clientCapabilities
      )
    }
  }
  
  @Test func testNotADirectory() async throws {
    // Create a file instead of directory
    let tempDir = FileManager.default.temporaryDirectory
    let filePath = tempDir.appendingPathComponent("notadirectory.txt")
    try "This is a file".write(to: filePath, atomically: true, encoding: .utf8)
    
    defer {
      try? FileManager.default.removeItem(at: filePath)
    }
    
    await #expect(throws: DXTTransportError.dxtDirectoryNotFound(filePath)) {
      _ = try await DXTTransport(
        dxtDirectory: filePath,
        clientInfo: TestFixtures.clientInfo,
        clientCapabilities: TestFixtures.clientCapabilities
      )
    }
  }
  
  @Test func testMissingManifest() async throws {
    // Create a directory without manifest.json
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    // Create a dummy file but no manifest
    let dummyFile = tempDir.appendingPathComponent("dummy.txt")
    try "dummy content".write(to: dummyFile, atomically: true, encoding: .utf8)
    
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    await #expect(throws: DXTTransportError.missingManifest) {
      _ = try await DXTTransport(
        dxtDirectory: tempDir,
        clientInfo: TestFixtures.clientInfo,
        clientCapabilities: TestFixtures.clientCapabilities
      )
    }
  }
  
  @Test func testUnsupportedPlatform() async throws {
    // Create a DXT with unsupported platform
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-unsupported-platform",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3"
        }
      },
      "compatibility": {
        "platforms": ["win32", "linux"]
      }
    }
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: "print('test')")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    await #expect(throws: DXTTransportError.unsupportedPlatform(supported: ["win32", "linux"])) {
      _ = try await DXTTransport(
        dxtDirectory: tempDir,
        clientInfo: TestFixtures.clientInfo,
        clientCapabilities: TestFixtures.clientCapabilities
      )
    }
  }
  
  @Test func testRuntimeVersionCheck() async throws {
    // Create a DXT with impossible Python version requirement
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-runtime-version",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3"
        }
      },
      "compatibility": {
        "runtimes": {
          "python": ">=99.0.0"
        }
      }
    }
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: "print('test')")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    do {
      _ = try await DXTTransport(
        dxtDirectory: tempDir,
        clientInfo: TestFixtures.clientInfo,
        clientCapabilities: TestFixtures.clientCapabilities
      )
      Issue.record("Expected runtime version mismatch error")
    } catch DXTTransportError.runtimeVersionMismatch(let runtime, _, _) {
      #expect(runtime == "python")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
  
  @Test func testEnvironmentVariableSubstitution() async throws {
    // Test ${__dirname}, ${HOME}, and platform-specific substitutions
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-env-substitution",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3",
          "args": ["${__dirname}/main.py", "${DOCUMENTS}/test.txt", "${pathSeparator}path"],
          "env": {
            "TEST_HOME": "${HOME}",
            "TEST_DIR": "${__dirname}",
            "TEST_DESKTOP": "${DESKTOP}",
            "TEST_DOWNLOADS": "${DOWNLOADS}",
            "TEST_SEP": "${/}"
          }
        }
      }
    }
    """
    
    let script = """
    import os
    import json
    import sys
    
    # MCP echo server that prints environment variables
    while True:
      line = sys.stdin.readline()
      if not line:
        break
      
      message = json.loads(line)
      if message.get("method") == "initialize":
        response = {
          "jsonrpc": "2.0",
          "id": message["id"],
          "result": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "serverInfo": {
              "name": "Test Server",
              "version": "1.0.0"
            }
          }
        }
        print(json.dumps(response))
        sys.stdout.flush()
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: script)
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    let transport = try await DXTTransport(
      dxtDirectory: tempDir,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities
    )
    try await transport.start()
    let initResult = try await withTimeout(
      5.0,
      timeoutMessage: "Initialize timed out after 5 seconds",
      defaultValue: InitializeResponse.Result(
        protocolVersion: "",
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: "", version: "")
      )
    ) {
      try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    }
    #expect(initResult.serverInfo.name == "Test Server")
    
    try await transport.close()
  }
  
  @Test func testAllVariableSubstitutions() throws {
    // Test all supported variable substitutions
    let manifestJSON = """
    {
      "dxt_version": "0.1",
      "name": "test-all-substitutions",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "${__dirname}/python3",
          "args": [
            "${__dirname}/main.py",
            "--home=${HOME}",
            "--desktop=${DESKTOP}",
            "--documents=${DOCUMENTS}",
            "--downloads=${DOWNLOADS}",
            "--sep=${pathSeparator}",
            "--sep2=${/}"
          ],
          "env": {
            "TEST_DIR": "${__dirname}",
            "TEST_HOME": "${HOME}",
            "TEST_DESKTOP": "${DESKTOP}",
            "TEST_DOCS": "${DOCUMENTS}",
            "TEST_DOWNLOADS": "${DOWNLOADS}",
            "TEST_SEP": "${/}"
          }
        }
      }
    }
    """
    
    // Parse the manifest
    let manifestData = manifestJSON.data(using: .utf8)!
    let manifest = try JSONDecoder().decode(DXTManifest.self, from: manifestData)
    
    // Create a test directory
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    
    // Build process info with substitutions
    let processInfo = try DXTTransport.buildProcessInfo(
      manifest: manifest,
      dxtDirectory: tempDir,
      userConfig: DXTUserConfigurationValues(),
      environment: nil,
      shellPath: nil
    )
    
    // The process info will have shell args: [shell, -c, command]
    #expect(processInfo.arguments?.count == 3)
    guard let args = processInfo.arguments, args.count >= 3 else {
      Issue.record("Process info arguments are missing or invalid")
      return
    }
    let fullCommand = args[2]
    
    // Verify command substitution
    #expect(fullCommand.contains("\(tempDir.path)/python3"))
    #expect(!fullCommand.contains("${__dirname}"))
    
    // Verify argument substitutions
    #expect(fullCommand.contains("\(tempDir.path)/main.py"))
    
    // Get expected system directories
    let fm = FileManager.default
    if let home = ProcessInfo.processInfo.environment["HOME"] ?? fm.homeDirectoryForCurrentUser.path as String? {
      #expect(fullCommand.contains("--home=\(home)"))
    }
    
    if let desktop = try? fm.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path {
      #expect(fullCommand.contains("--desktop=\(desktop)"))
    }
    
    if let documents = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path {
      #expect(fullCommand.contains("--documents=\(documents)"))
    }
    
    if let downloads = try? fm.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path {
      #expect(fullCommand.contains("--downloads=\(downloads)"))
    }
    
    // Path separator should be /
    #expect(fullCommand.contains("--sep=/"))
    #expect(fullCommand.contains("--sep2=/"))
    #expect(!fullCommand.contains("${pathSeparator}"))
    #expect(!fullCommand.contains("${/}"))
    
    // Verify environment variable substitutions
    let env = processInfo.environment ?? [:]
    #expect(env["TEST_DIR"] == tempDir.path)
    #expect(env["TEST_HOME"] != nil && !env["TEST_HOME"]!.contains("${HOME}"))
    #expect(env["TEST_DESKTOP"] != nil && !env["TEST_DESKTOP"]!.contains("${DESKTOP}"))
    #expect(env["TEST_DOCS"] != nil && !env["TEST_DOCS"]!.contains("${DOCUMENTS}"))
    #expect(env["TEST_DOWNLOADS"] != nil && !env["TEST_DOWNLOADS"]!.contains("${DOWNLOADS}"))
    #expect(env["TEST_SEP"] == "/")
  }
  
  @Test func testWorkingDirectorySubstitution() throws {
    // Test substitutions in working directory
    let manifestJSON = """
    {
      "dxt_version": "0.1",
      "name": "test-workdir-substitution",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3",
          "args": ["main.py"],
          "working_directory": "${DOCUMENTS}/myapp"
        }
      }
    }
    """
    
    // Parse the manifest
    let manifestData = manifestJSON.data(using: .utf8)!
    let manifest = try JSONDecoder().decode(DXTManifest.self, from: manifestData)
    
    // Create a test directory
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    
    // Build process info with substitutions
    let processInfo = try DXTTransport.buildProcessInfo(
      manifest: manifest,
      dxtDirectory: tempDir,
      userConfig: DXTUserConfigurationValues(),
      environment: nil,
      shellPath: nil
    )
    
    // Verify working directory substitution
    let fm = FileManager.default
    if let documents = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path {
      #expect(processInfo.currentDirectoryURL?.path == "\(documents)/myapp")
    }
  }
  
  @Test func testPlatformOverrides() async throws {
    // Test platform-specific overrides
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-platform-overrides",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python",
          "args": ["main.py"]
        }
      },
      "compatibility": {
        "platform_overrides": {
          "darwin": {
            "command": "python3",
            "args": ["${__dirname}/main.py", "--darwin"],
            "env": {
              "PLATFORM": "darwin"
            }
          }
        }
      }
    }
    """
    
    let script = """
    import json
    import sys
    
    while True:
      line = sys.stdin.readline()
      if not line:
        break
      
      message = json.loads(line)
      if message.get("method") == "initialize":
        response = {
          "jsonrpc": "2.0",
          "id": message["id"],
          "result": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "serverInfo": {
              "name": "Platform Override Test",
              "version": "1.0.0"
            }
          }
        }
        print(json.dumps(response))
        sys.stdout.flush()
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: script)
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    let transport = try await DXTTransport(
      dxtDirectory: tempDir,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities
    )
    try await transport.start()
    let initResult = try await withTimeout(
      5.0,
      timeoutMessage: "Initialize timed out after 5 seconds",
      defaultValue: InitializeResponse.Result(
        protocolVersion: "",
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: "", version: "")
      )
    ) {
      try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    }
    #expect(initResult.serverInfo.name == "Platform Override Test")
    
    try await transport.close()
  }
  
  @Test func testContextVersionCheck() async throws {
    // Test Context app version requirement
    // Since we're running in tests, Bundle.main won't have the Context app version
    // So we test the manifest parsing and error handling
    
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-context-version",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3"
        }
      },
      "compatibility": {
        "context": ">=1.0.0"
      }
    }
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: "print('test')")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    // In test environment, Bundle.main won't have CFBundleShortVersionString,
    // so the check should pass (early return in validateContextVersion)
    let transport = try await DXTTransport(
      dxtDirectory: tempDir,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities
    )
    
    // If we get here without throwing, the test passes
    _ = transport
  }
  
  @Test func testContextVersionManifestParsing() throws {
    // Test that the manifest correctly parses context version requirement
    let manifestJSON = """
    {
      "dxt_version": "0.1",
      "name": "test",
      "version": "1.0.0",
      "description": "Test",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3"
        }
      },
      "compatibility": {
        "context": ">=2.0.0 <3.0.0",
        "claude_desktop": ">=0.7.0",
        "platforms": ["darwin"],
        "runtimes": {
          "python": ">=3.8.0"
        }
      }
    }
    """
    
    let manifestData = manifestJSON.data(using: .utf8)!
    let manifest = try JSONDecoder().decode(DXTManifest.self, from: manifestData)
    
    #expect(manifest.compatibility?.context == ">=2.0.0 <3.0.0")
    #expect(manifest.compatibility?.claudeDesktop == ">=0.7.0")
    #expect(manifest.compatibility?.platforms == ["darwin"])
    #expect(manifest.compatibility?.runtimes?["python"] == ">=3.8.0")
  }
  
  @Test func testValidateManifestCompatibility() throws {
    // Test the public static validation method
    let manifestJSON = """
    {
      "dxt_version": "0.1",
      "name": "test-validate",
      "version": "1.0.0",
      "description": "Test",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3"
        }
      },
      "compatibility": {
        "platforms": ["darwin"],
        "runtimes": {
          "python": ">=3.0.0"
        }
      }
    }
    """
    
    let manifestData = manifestJSON.data(using: .utf8)!
    let manifest = try JSONDecoder().decode(DXTManifest.self, from: manifestData)
    
    // Should not throw for valid compatibility
    try DXTTransport.validateManifestCompatibility(manifest)
  }
  
  @Test func testContextVersionVariousFormats() throws {
    // Test various context version requirement formats
    let testCases = [
      (">=1.0.0", "Simple minimum version"),
      (">=1.0.0 <2.0.0", "Version range"),
      ("~>1.2.0", "Pessimistic constraint"),
      (">=1.0.0 || >=2.0.0", "OR conditions"),
      ("1.5.0", "Exact version")
    ]
    
    for (versionReq, description) in testCases {
      let manifestJSON = """
      {
        "dxt_version": "0.1",
        "name": "test-\(description.replacingOccurrences(of: " ", with: "-"))",
        "version": "1.0.0",
        "description": "\(description)",
        "author": {"name": "Test"},
        "server": {
          "type": "python",
          "entry_point": "main.py",
          "mcp_config": {
            "command": "python3"
          }
        },
        "compatibility": {
          "context": "\(versionReq)"
        }
      }
      """
      
      let manifestData = manifestJSON.data(using: .utf8)!
      let manifest = try JSONDecoder().decode(DXTManifest.self, from: manifestData)
      
      #expect(manifest.compatibility?.context == versionReq, "Failed for: \(description)")
    }
  }
  
  @Test func testContextVersionEdgeCases() throws {
    // Test edge cases for context version checking
    
    // Test with no compatibility section
    let noCompatJSON = """
    {
      "dxt_version": "0.1",
      "name": "test-no-compat",
      "version": "1.0.0",
      "description": "Test",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3"
        }
      }
    }
    """
    
    let noCompatData = noCompatJSON.data(using: .utf8)!
    let noCompatManifest = try JSONDecoder().decode(DXTManifest.self, from: noCompatData)
    
    // Should not throw when no compatibility section exists
    try DXTTransport.validateManifestCompatibility(noCompatManifest)
    
    // Test with empty compatibility section
    let emptyCompatJSON = """
    {
      "dxt_version": "0.1",
      "name": "test-empty-compat",
      "version": "1.0.0",
      "description": "Test",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3"
        }
      },
      "compatibility": {}
    }
    """
    
    let emptyCompatData = emptyCompatJSON.data(using: .utf8)!
    let emptyCompatManifest = try JSONDecoder().decode(DXTManifest.self, from: emptyCompatData)
    
    // Should not throw when compatibility section is empty
    try DXTTransport.validateManifestCompatibility(emptyCompatManifest)
  }
  
  @Test func testPythonVersionCheckWithFallback() throws {
    // Test that Python version checking works with both "python" and "python3"
    // This test verifies the fallback mechanism works in real environments
    
    let manifestJSON = """
    {
      "dxt_version": "0.1",
      "name": "test-python-version",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python"
        }
      },
      "compatibility": {
        "runtimes": {
          "python": ">=3.0.0"
        }
      }
    }
    """
    
    let manifestData = manifestJSON.data(using: .utf8)!
    let manifest = try JSONDecoder().decode(DXTManifest.self, from: manifestData)
    
    // This should not throw if either "python" or "python3" exists with version >= 3.0.0
    do {
      try DXTTransport.validateManifestCompatibility(manifest)
    } catch DXTTransportError.runtimeNotInstalled {
      // This is okay if neither python nor python3 are installed
      // (shouldn't happen in CI but could in some environments)
    } catch DXTTransportError.runtimeVersionMismatch(_, _, let installed) {
      // This is okay if the installed version is < 3.0.0
      // Just verify we got a version string
      #expect(!installed.isEmpty)
    }
  }
  
  // MARK: - Helper Functions
  
  private func extractDXT(at dxtURL: URL) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    let archive = try Archive(url: dxtURL, accessMode: .read)
    
    // Extract all files
    for entry in archive {
      // Skip symlinks as they can cause issues
      if entry.type == .symlink {
        continue
      }
      
      let destinationURL = tempDir.appendingPathComponent(entry.path)
      
      // Create directories as needed
      if entry.type == .directory {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        continue
      }
      
      // Create parent directory if needed
      let parentDir = destinationURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
      
      // Extract file
      _ = try archive.extract(entry, to: destinationURL)
    }
    
    // Find the actual DXT directory (it might be nested)
    let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
    if contents.count == 1, 
       let firstItem = contents.first,
       let isDirectory = try? firstItem.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
       isDirectory == true {
      // The DXT was extracted with a top-level directory
      return firstItem
    }
    
    return tempDir
  }
  
  private func createTestDXTDirectory(manifest: String, entryPoint: String) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    
    // Write manifest
    let manifestPath = tempDir.appendingPathComponent("manifest.json")
    try manifest.write(to: manifestPath, atomically: true, encoding: .utf8)
    
    // Write entry point
    let entryPath = tempDir.appendingPathComponent("main.py")
    try entryPoint.write(to: entryPath, atomically: true, encoding: .utf8)
    
    return tempDir
  }
  
  // MARK: - User Configuration Tests
  
  @Test func testUserConfigSubstitution() async throws {
    // Create a DXT with user configuration
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-user-config",
      "version": "1.0.0",
      "description": "Test server with user config",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "echo",
          "args": ["api_key=${user_config.api_key}", "max=${user_config.max_requests}", "enabled=${user_config.enabled}"],
          "env": {
            "API_KEY": "${user_config.api_key}",
            "MAX_REQUESTS": "${user_config.max_requests}"
          }
        }
      },
      "user_config": {
        "api_key": {
          "type": "string",
          "title": "API Key",
          "required": true,
          "sensitive": true
        },
        "max_requests": {
          "type": "number",
          "title": "Max Requests",
          "default": 100
        },
        "enabled": {
          "type": "boolean",
          "title": "Enabled",
          "default": true
        }
      }
    }
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: "print('test')")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Test with user config values
    let userConfig = DXTUserConfigurationValues(values: [
      "api_key": DXTUserConfigurationValues.ConfigValue(
        value: .string("test-api-key"),
        isSensitive: false,  // Already resolved from keychain
        configType: "string"
      ),
      "max_requests": DXTUserConfigurationValues.ConfigValue(
        value: .number(200),
        isSensitive: false,
        configType: "number"
      ),
      "enabled": DXTUserConfigurationValues.ConfigValue(
        value: .boolean(true),
        isSensitive: false,
        configType: "boolean"
      )
    ])
    
    let transport = try await DXTTransport(
      dxtDirectory: tempDir,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities,
      userConfig: userConfig
    )
    
    // Verify the transport was created successfully
    let manifestName = await transport.manifest.name
    #expect(manifestName == "test-user-config")
  }
  
  @Test func testUserConfigArrayExpansion() async throws {
    // Create a DXT with array user configuration
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-array-config",
      "version": "1.0.0",
      "description": "Test server with array config",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "echo",
          "args": ["--dir", "${user_config.allowed_dirs}", "--end"]
        }
      },
      "user_config": {
        "allowed_dirs": {
          "type": "directory",
          "title": "Allowed Directories",
          "multiple": true,
          "required": true
        }
      }
    }
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: "print('test')")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Test with array values - use temp directories that exist
    let tempDir1 = FileManager.default.temporaryDirectory.appendingPathComponent("test-dir-1-\(UUID().uuidString)")
    let tempDir2 = FileManager.default.temporaryDirectory.appendingPathComponent("test-dir-2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tempDir2, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: tempDir1)
      try? FileManager.default.removeItem(at: tempDir2)
    }
    
    let userConfig = DXTUserConfigurationValues(values: [
      "allowed_dirs": DXTUserConfigurationValues.ConfigValue(
        value: .stringArray([tempDir1.path, tempDir2.path]),
        isSensitive: false,
        configType: "directory"
      )
    ])
    
    let transport = try await DXTTransport(
      dxtDirectory: tempDir,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities,
      userConfig: userConfig
    )
    
    // The args should be expanded to ["--dir", "/home/user/docs", "/home/user/projects", "--end"]
    let manifestName = await transport.manifest.name
    #expect(manifestName == "test-array-config")
  }
  
  @Test func testMissingRequiredUserConfig() async throws {
    // Create a DXT with required user configuration
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-required-config",
      "version": "1.0.0",
      "description": "Test server with required config",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3",
          "args": ["${user_config.api_key}"]
        }
      },
      "user_config": {
        "api_key": {
          "type": "string",
          "title": "API Key",
          "required": true
        }
      }
    }
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: "print('test')")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Test without providing required config
    await #expect(throws: DXTTransportError.missingRequiredConfig(key: "api_key")) {
      _ = try await DXTTransport(
        dxtDirectory: tempDir,
        clientInfo: TestFixtures.clientInfo,
        clientCapabilities: TestFixtures.clientCapabilities,
        userConfig: nil
      )
    }
  }
  
  @Test func testSensitiveValuesNotAllowed() async throws {
    // Create a DXT with user configuration
    let manifest = """
    {
      "dxt_version": "0.1",
      "name": "test-sensitive",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3"
        }
      },
      "user_config": {
        "api_key": {
          "type": "string",
          "title": "API Key",
          "sensitive": true
        }
      }
    }
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifest, entryPoint: "print('test')")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Test with sensitive value not as keychain reference
    let userConfig = DXTUserConfigurationValues(values: [
      "api_key": DXTUserConfigurationValues.ConfigValue(
        value: .string("sensitive-value"),
        isSensitive: true,  // Still marked as sensitive
        configType: "string"
      )
    ])
    
    do {
      _ = try await DXTTransport(
        dxtDirectory: tempDir,
        clientInfo: TestFixtures.clientInfo,
        clientCapabilities: TestFixtures.clientCapabilities,
        userConfig: userConfig
      )
      Issue.record("Expected error for sensitive values")
    } catch {
      // Expected to throw an error
    }
  }
  
  @Test func testGlobalEnvironmentMerging() async throws {
    // Test that global environment is merged correctly with manifest environment
    let manifestJSON = """
    {
      "dxt_version": "0.1",
      "name": "test-global-env",
      "version": "1.0.0",
      "description": "Test server for global environment",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3",
          "args": ["${__dirname}/main.py"],
          "env": {
            "MANIFEST_VAR": "manifest_value",
            "OVERRIDE_VAR": "manifest_override"
          }
        }
      }
    }
    """
    
    let script = """
    import os
    import json
    import sys
    
    # MCP echo server that returns environment variables in initialize response
    while True:
      line = sys.stdin.readline()
      if not line:
        break
      
      message = json.loads(line)
      if message.get("method") == "initialize":
        # Include environment variables in the version string for testing
        env_info = {
          "GLOBAL_VAR": os.environ.get("GLOBAL_VAR", "not_set"),
          "MANIFEST_VAR": os.environ.get("MANIFEST_VAR", "not_set"),
          "OVERRIDE_VAR": os.environ.get("OVERRIDE_VAR", "not_set")
        }
        
        response = {
          "jsonrpc": "2.0",
          "id": message["id"],
          "result": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "serverInfo": {
              "name": "Test Server",
              "version": json.dumps(env_info)
            }
          }
        }
        print(json.dumps(response))
        sys.stdout.flush()
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifestJSON, entryPoint: script)
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Create transport with global environment
    let globalEnvironment = [
      "GLOBAL_VAR": "global_value",
      "OVERRIDE_VAR": "global_override"  // This should be overridden by manifest
    ]
    
    let transport = try await DXTTransport(
      dxtDirectory: tempDir,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities,
      userConfig: nil,
      environment: globalEnvironment
    )
    
    try await transport.start()
    let initResult = try await withTimeout(
      5.0,
      timeoutMessage: "Initialize timed out after 5 seconds",
      defaultValue: InitializeResponse.Result(
        protocolVersion: "",
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: "", version: "")
      )
    ) {
      try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    }
    
    // Parse the version string to check environment variables
    if let versionData = initResult.serverInfo.version.data(using: .utf8),
       let envInfo = try? JSONDecoder().decode([String: String].self, from: versionData) {
      #expect(envInfo["GLOBAL_VAR"] == "global_value")  // Global environment set
      #expect(envInfo["MANIFEST_VAR"] == "manifest_value")  // Manifest environment set
      #expect(envInfo["OVERRIDE_VAR"] == "manifest_override")  // Manifest takes precedence
    } else {
      Issue.record("Failed to parse environment info from version string")
    }
    
    try await transport.close()
  }
  
  @Test func testEmptyGlobalEnvironment() async throws {
    // Test that empty global environment doesn't affect anything
    let manifestJSON = """
    {
      "dxt_version": "0.1",
      "name": "test-empty-env",
      "version": "1.0.0",
      "description": "Test server",
      "author": {"name": "Test"},
      "server": {
        "type": "python",
        "entry_point": "main.py",
        "mcp_config": {
          "command": "python3",
          "args": ["${__dirname}/main.py"],
          "env": {
            "TEST_VAR": "test_value"
          }
        }
      }
    }
    """
    
    let script = """
    import os
    import json
    import sys
    
    while True:
      line = sys.stdin.readline()
      if not line:
        break
      
      message = json.loads(line)
      if message.get("method") == "initialize":
        test_var = os.environ.get("TEST_VAR", "not_set")
        response = {
          "jsonrpc": "2.0",
          "id": message["id"],
          "result": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "serverInfo": {
              "name": "Test Server",
              "version": test_var
            }
          }
        }
        print(json.dumps(response))
        sys.stdout.flush()
    """
    
    let tempDir = try createTestDXTDirectory(manifest: manifestJSON, entryPoint: script)
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Create transport with empty global environment
    let transport = try await DXTTransport(
      dxtDirectory: tempDir,
      clientInfo: TestFixtures.clientInfo,
      clientCapabilities: TestFixtures.clientCapabilities,
      userConfig: nil,
      environment: [:]  // Empty environment
    )
    
    try await transport.start()
    let initResult = try await withTimeout(
      5.0,
      timeoutMessage: "Initialize timed out after 5 seconds", 
      defaultValue: InitializeResponse.Result(
        protocolVersion: "",
        capabilities: ServerCapabilities(),
        serverInfo: Implementation(name: "", version: "")
      )
    ) {
      try await transport.initialize(idGenerator: TestFixtures.idGenerator)
    }
    
    // Verify manifest environment is still applied
    #expect(initResult.serverInfo.version == "test_value")
    
    try await transport.close()
  }
}
