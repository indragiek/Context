// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Foundation
import os

// MARK: - DXT Errors

enum DXTError: LocalizedError {
  case failedToExtract(any Error)
  case manifestNotFound
  case invalidManifest(any Error)
  case temporaryDirectoryCreationFailed(any Error)
  case invalidZipFile(any Error)

  var errorDescription: String? {
    switch self {
    case .failedToExtract(let error):
      return "Failed to extract DXT file: \(error.localizedDescription)"
    case .manifestNotFound:
      return "manifest.json not found in DXT package"
    case .invalidManifest(let error):
      return "Invalid manifest.json: \(error.localizedDescription)"
    case .temporaryDirectoryCreationFailed(let error):
      return "Failed to create temporary directory: \(error.localizedDescription)"
    case .invalidZipFile(let error):
      return "The selected file is not a valid DXT package: \(error.localizedDescription)"
    }
  }
}

@Reducer
struct DXTConfigFeature {

  @ObservableState
  struct State: Equatable {
    var filePath: URL?
    var tempDirectory: URL?
    var manifest: DXTManifest?
    var manifestData: Data?
    var userConfig: DXTUserConfigurationValues = DXTUserConfigurationValues()
    var isProcessing: Bool = false
    var error: String?

    init() {}

    init(from config: DXTConfig) {
      self.filePath = config.filePath
      self.tempDirectory = config.tempDirectory
      self.manifest = config.manifest
      self.manifestData = config.manifestData
      self.userConfig = config.userConfig
    }

    var asConfig: DXTConfig {
      DXTConfig(
        filePath: filePath,
        tempDirectory: tempDirectory,
        manifest: manifest,
        manifestData: manifestData,
        userConfig: userConfig
      )
    }

    var missingRequiredFields: [String] {
      guard let manifest = manifest else { return [] }
      return userConfig.missingRequiredKeys(from: manifest)
    }
  }

  enum Action {
    case fileSelected(URL)
    case fileProcessed(Result<(URL, DXTManifest, Data), any Error>)
    case userConfigChanged(DXTUserConfigurationValues)
    case clearError
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.dxtStore) var dxtStore
  private let logger = Logger(subsystem: "com.indragie.Context", category: "DXTConfigFeature")

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .fileSelected(url):
        state.isProcessing = true
        state.error = nil

        // Clean up any existing temporary directory
        if let existingTempDir = state.tempDirectory {
          dxtStore.cleanupTempDirectory(existingTempDir)
          state.tempDirectory = nil
        }

        return .run { [dxtStore] send in
          do {
            let result = try await dxtStore.processFile(at: url)
            await send(
              .fileProcessed(.success((result.tempDir, result.manifest, result.manifestData))))
          } catch {
            await send(.fileProcessed(.failure(error)))
          }
        }

      case let .fileProcessed(result):
        state.isProcessing = false

        switch result {
        case let .success((tempDir, manifest, manifestData)):
          state.tempDirectory = tempDir
          state.manifest = manifest
          state.manifestData = manifestData

        case let .failure(error):
          state.error = error.localizedDescription
        }
        return .none

      case let .userConfigChanged(userConfig):
        state.userConfig = userConfig
        return .none

      case .clearError:
        state.error = nil
        return .none
      }
    }
  }
}
