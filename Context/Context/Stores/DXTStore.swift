// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation
import ZIPFoundation
import os

// MARK: - DXT Processing Result

struct DXTProcessingResult: Equatable, Sendable {
  let tempDir: URL
  let manifest: DXTManifest
  let manifestData: Data
  let requiresUserConfig: Bool

  var serverName: String {
    manifest.displayName ?? manifest.name
  }
}

// MARK: - DXT Store Protocol

protocol DXTStoreProtocol: Sendable {
  /// Validates and extracts a DXT package
  func processFile(at url: URL) async throws -> DXTProcessingResult

  /// Checks if a manifest requires user configuration
  func requiresUserConfiguration(_ manifest: DXTManifest) -> Bool

  /// Installs a DXT server to its final location
  func installServer(from tempDir: URL, serverID: UUID, mode: AddServerMode) async throws -> URL

  /// Creates an MCPServer record from a DXT manifest
  func createServer(from manifest: DXTManifest, serverID: UUID, installPath: URL) -> MCPServer

  /// Gets the directory path for a DXT server
  func serverDirectory(for serverID: UUID) throws -> URL

  /// Gets the version of an installed DXT server
  func getServerVersion(_ server: MCPServer) -> String?

  /// Cleans up a temporary directory
  func cleanupTempDirectory(_ tempDir: URL?)
}

// MARK: - DXT Store Implementation

struct DXTStore: DXTStoreProtocol {
  private let logger = Logger(subsystem: "com.indragie.Context", category: "DXTStore")

  func processFile(at url: URL) async throws -> DXTProcessingResult {
    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    do {
      try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    } catch {
      throw DXTError.temporaryDirectoryCreationFailed(error)
    }

    // Extract the DXT file
    do {
      try fileManager.unzipItem(at: url, to: tempDir)
    } catch {
      // Clean up temp directory on failure
      try? fileManager.removeItem(at: tempDir)

      if let archiveError = error as? Archive.ArchiveError {
        throw DXTError.invalidZipFile(archiveError)
      } else {
        throw DXTError.failedToExtract(error)
      }
    }

    // Parse the manifest
    let manifestURL = tempDir.appendingPathComponent("manifest.json")
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      try? fileManager.removeItem(at: tempDir)
      throw DXTError.manifestNotFound
    }

    let manifestData = try Data(contentsOf: manifestURL)

    do {
      let manifest = try JSONDecoder().decode(DXTManifest.self, from: manifestData)
      let requiresConfig = requiresUserConfiguration(manifest)

      return DXTProcessingResult(
        tempDir: tempDir,
        manifest: manifest,
        manifestData: manifestData,
        requiresUserConfig: requiresConfig
      )
    } catch {
      try? fileManager.removeItem(at: tempDir)
      throw DXTError.invalidManifest(error)
    }
  }

  func requiresUserConfiguration(_ manifest: DXTManifest) -> Bool {
    manifest.userConfig?.contains { $0.value.required == true } ?? false
  }

  func installServer(from tempDir: URL, serverID: UUID, mode: AddServerMode) async throws -> URL {
    let fileManager = FileManager.default

    // Get the server directory path
    let serverDir = try serverDirectory(for: serverID)

    // Create parent directories if they don't exist
    let dxtDir = serverDir.deletingLastPathComponent()
    try fileManager.createDirectory(at: dxtDir, withIntermediateDirectories: true)

    // Install from temp directory
    if tempDir != serverDir {
      try await performFileInstall(from: tempDir, to: serverDir)
    }
    // If tempDir == serverDir, it means we're in edit mode without a new file,
    // so we don't need to do anything

    return serverDir
  }

  func createServer(from manifest: DXTManifest, serverID: UUID, installPath: URL) -> MCPServer {
    MCPServer(
      id: serverID,
      name: manifest.displayName ?? manifest.name,
      transport: .dxt,
      url: installPath.absoluteString
    )
  }

  func serverDirectory(for serverID: UUID) throws -> URL {
    let fileManager = FileManager.default
    let appSupportURL = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let contextDir = appSupportURL.appendingPathComponent("Context", isDirectory: true)
    let dxtDir = contextDir.appendingPathComponent("dxt", isDirectory: true)
    return dxtDir.appendingPathComponent(serverID.uuidString, isDirectory: true)
  }

  func getServerVersion(_ server: MCPServer) -> String? {
    guard server.transport == .dxt,
      let urlString = server.url,
      let url = URL(string: urlString)
    else {
      return nil
    }

    let manifestURL = url.appendingPathComponent("manifest.json")
    guard let manifestData = try? Data(contentsOf: manifestURL),
      let manifest = try? JSONDecoder().decode(DXTManifest.self, from: manifestData)
    else {
      return nil
    }

    return manifest.version
  }

  func cleanupTempDirectory(_ tempDir: URL?) {
    guard let tempDir = tempDir else { return }

    // Safety check: Only delete if it's actually in a temp directory
    let path = tempDir.path
    let fileManager = FileManager.default
    let tempDirPath = fileManager.temporaryDirectory.path

    guard
      path.hasPrefix(tempDirPath) || path.contains("/var/tmp/") || path.contains("/tmp/")
        || path.contains("/private/var/") || path.contains("/private/tmp/")
    else {
      logger.error("Refusing to delete non-temporary directory: \(path)")
      return
    }

    do {
      try fileManager.removeItem(at: tempDir)
      logger.info("Cleaned up temporary directory: \(path)")
    } catch {
      logger.error("Failed to clean up temporary directory: \(error)")
    }
  }

  // MARK: - Private Methods

  private func performFileInstall(from tempDir: URL, to serverDir: URL) async throws {
    let fileManager = FileManager.default

    // Create a backup of existing directory if it exists
    var backupDir: URL?
    if fileManager.fileExists(atPath: serverDir.path) {
      backupDir = serverDir.appendingPathExtension("backup")
      // Remove old backup if it exists
      do {
        try fileManager.removeItem(at: backupDir!)
      } catch {
        logger.warning("Failed to remove old backup: \(error)")
      }
      try fileManager.moveItem(at: serverDir, to: backupDir!)
    }

    do {
      // Use file coordination for atomic directory replacement
      var coordinationError: NSError?
      var copyError: NSError?
      let coordinator = NSFileCoordinator(filePresenter: nil)

      coordinator.coordinate(
        writingItemAt: serverDir, options: .forReplacing, error: &coordinationError
      ) { (writableURL) in
        do {
          // Copy from temp directory (new installation or update)
          try fileManager.copyItem(at: tempDir, to: writableURL)
        } catch let fileError {
          copyError = fileError as NSError
        }
      }

      if let error = coordinationError ?? copyError {
        throw error
      }

      // Success - remove backup and temp directory
      if let backup = backupDir {
        do {
          try fileManager.removeItem(at: backup)
        } catch {
          logger.warning("Failed to remove backup directory: \(error)")
        }
      }
      do {
        try fileManager.removeItem(at: tempDir)
      } catch {
        logger.warning("Failed to remove temp directory: \(error)")
      }

    } catch {
      // Failed - restore backup if it exists
      if let backup = backupDir, fileManager.fileExists(atPath: backup.path) {
        // Remove partially copied directory if it exists
        do {
          try fileManager.removeItem(at: serverDir)
        } catch {
          logger.error("Failed to remove partially copied directory: \(error)")
        }
        // Restore backup
        do {
          try fileManager.moveItem(at: backup, to: serverDir)
        } catch {
          logger.error("Failed to restore backup: \(error)")
        }
      }
      throw error
    }
  }
}

// MARK: - Dependency Registration

private enum DXTStoreKey: DependencyKey {
  static let liveValue: any DXTStoreProtocol = DXTStore()
}

extension DependencyValues {
  var dxtStore: any DXTStoreProtocol {
    get { self[DXTStoreKey.self] }
    set { self[DXTStoreKey.self] = newValue }
  }
}
