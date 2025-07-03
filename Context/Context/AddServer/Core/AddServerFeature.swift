// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation
import GRDB
import SharingGRDB
import os

// MARK: - Mode

enum AddServerMode: Equatable {
  case add
  case edit(originalServer: MCPServer)
}

// MARK: - Screen State

enum AddServerScreen: Equatable {
  case form
  case error(String)
}

// MARK: - Validation

struct ValidationState: Equatable {
  var serverNameError: String?
  var isValid: Bool

  static let valid = ValidationState(serverNameError: nil, isValid: true)
  static let invalid = ValidationState(serverNameError: nil, isValid: false)
}

// MARK: - Transport Configuration

enum TransportConfig: Equatable {
  case stdio(StdioConfig)
  case http(HTTPConfig)
  case dxt(DXTConfig)

  static func defaultConfig(for transport: TransportType) -> TransportConfig {
    switch transport {
    case .stdio:
      return .stdio(StdioConfig())
    case .sse, .streamableHTTP:
      return .http(HTTPConfig())
    case .dxt:
      return .dxt(DXTConfig())
    }
  }
}

struct StdioConfig: Equatable {
  var command: String = ""
  var arguments: [ArgumentItem] = []
  var selectedArgumentId: ArgumentItem.ID?
  var environmentVariables: [EnvironmentVariableItem] = []
  var selectedEnvironmentId: EnvironmentVariableItem.ID?
  var stdioTab: StdioTab = .arguments
}

struct HTTPConfig: Equatable {
  var url: String = ""
  var headers: [HeaderItem] = []
  var selectedHeaderId: HeaderItem.ID?
}

struct DXTConfig: Equatable {
  var filePath: URL?
  var tempDirectory: URL?
  var manifest: DXTManifest?
  var manifestData: Data?
  var userConfig: DXTUserConfigurationValues = DXTUserConfigurationValues()
}

struct HeaderItem: Equatable, Identifiable {
  let id = UUID()
  var key: String = ""
  var value: String = ""
  var shouldFocusKey: Bool = false
}

struct EnvironmentVariableItem: Equatable, Identifiable {
  let id = UUID()
  var name: String = ""
  var value: String = ""
  var shouldFocusName: Bool = false
}

enum StdioTab: String, CaseIterable {
  case arguments = "Arguments"
  case environment = "Environment"
}

@Reducer
struct AddServerFeature {

  @ObservableState
  struct State: Equatable {
    var mode: AddServerMode = .add
    var screen: AddServerScreen = .form
    var serverName: String = ""
    var transport: TransportType = .streamableHTTP
    var serverNameManuallyEdited: Bool = false

    // Transport configurations
    var stdioConfig = StdioConfigFeature.State()
    var httpConfig = HTTPConfigFeature.State()
    var dxtConfig = DXTConfigFeature.State()

    // Validation
    var validation: ValidationState = .invalid

    // Computed properties
    var serverNameError: String? {
      validation.serverNameError
    }

    var isValid: Bool {
      validation.isValid
    }

    var transportDisplayName: String {
      switch transport {
      case .stdio:
        return "stdio"
      case .sse:
        return "HTTP+SSE"
      case .streamableHTTP:
        return "Streamable HTTP"
      case .dxt:
        return "DXT"
      }
    }

    var transportConfig: TransportConfig {
      switch transport {
      case .stdio:
        return .stdio(stdioConfig.asConfig)
      case .sse, .streamableHTTP:
        return .http(httpConfig.asConfig)
      case .dxt:
        return .dxt(dxtConfig.asConfig)
      }
    }

    // Default initializer for add mode
    init() {
      self.mode = .add
      self.transport = .streamableHTTP
    }

    // Initializer for edit mode
    init(editingServer server: MCPServer) {
      self.mode = .edit(originalServer: server)
      self.serverName = server.name
      self.serverNameManuallyEdited = true  // In edit mode, assume name was manually set

      // Map deprecated .sse transport to .streamableHTTP
      if server.transport == .sse {
        self.transport = .streamableHTTP
      } else {
        self.transport = server.transport
      }

      // Initialize transport-specific configurations
      switch server.transport {
      case .stdio:
        var config = StdioConfig()
        config.command = server.command ?? ""

        if let args = server.args {
          config.arguments = args.map { ArgumentItem(value: $0) }
        }

        if let env = server.environment {
          config.environmentVariables = env.map { key, value in
            EnvironmentVariableItem(name: key, value: value)
          }
        }

        self.stdioConfig = StdioConfigFeature.State(from: config)

      case .sse, .streamableHTTP:
        var config = HTTPConfig()
        config.url = server.url ?? ""

        if let headers = server.headers {
          config.headers = headers.map { key, value in
            HeaderItem(key: key, value: value)
          }
        }

        self.httpConfig = HTTPConfigFeature.State(from: config)

      case .dxt:
        var config = DXTConfig()

        // For DXT servers in edit mode, try to load the manifest
        if let urlString = server.url, let url = URL(string: urlString) {
          let manifestURL = url.appendingPathComponent("manifest.json")
          if let manifestData = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(DXTManifest.self, from: manifestData)
          {
            config.manifest = manifest
            config.manifestData = manifestData
            // DO NOT set tempDirectory here - this is the actual installation!
            // tempDirectory should only be set when extracting a new DXT file

            if let userConfig = server.dxtUserConfig {
              config.userConfig = userConfig
            }
          }
        }

        self.dxtConfig = DXTConfigFeature.State(from: config)
      }
    }
  }

  enum Action {
    case serverNameChanged(String)
    case transportChanged(TransportType)
    case saveButtonTapped
    case serverSaved(Result<UUID, any Error>)
    case doneButtonTapped
    case cancelButtonTapped
    case loadDXTFile(tempDir: URL, manifest: DXTManifest, manifestData: Data)

    // Transport actions
    case stdioConfig(StdioConfigFeature.Action)
    case httpConfig(HTTPConfigFeature.Action)
    case dxtConfig(DXTConfigFeature.Action)

    // Internal actions
    case validateState
    case setValidation(ValidationState)
  }

  @Dependency(\.dismiss) var dismiss
  @Dependency(\.serverStore) var serverStore
  @Dependency(\.dxtStore) var dxtStore
  @Dependency(\.dxtConfigKeychain) var dxtConfigKeychain
  private let logger = Logger(subsystem: "com.indragie.Context", category: "AddServerFeature")

  var body: some ReducerOf<Self> {
    Scope(state: \.stdioConfig, action: \.stdioConfig) {
      StdioConfigFeature()
    }

    Scope(state: \.httpConfig, action: \.httpConfig) {
      HTTPConfigFeature()
    }

    Scope(state: \.dxtConfig, action: \.dxtConfig) {
      DXTConfigFeature()
    }

    Reduce { state, action in
      switch action {
      case let .serverNameChanged(name):
        state.serverName = name

        // Only mark as manually edited if the user actually typed something different
        // from what would be auto-generated
        if !name.isEmpty {
          // Check if this name is different from what would be auto-generated from current URL
          let autoGeneratedName = URLHelpers.extractHostName(from: state.httpConfig.url) ?? ""
          if name != autoGeneratedName {
            state.serverNameManuallyEdited = true
          }
        } else {
          // If the name is cleared, allow auto-generation again
          state.serverNameManuallyEdited = false
        }

        return .send(.validateState)

      case let .transportChanged(transport):
        state.transport = transport
        return .send(.validateState)

      case .saveButtonTapped:
        return saveServer(state: state)

      case let .serverSaved(result):
        switch result {
        case .success:
          return .run { _ in
            await dismiss()
          }
        case let .failure(error):
          state.screen = .error(error.localizedDescription)
        }
        return .none

      case .doneButtonTapped:
        return .run { _ in
          await dismiss()
        }

      case .cancelButtonTapped:
        return .run { _ in
          await dismiss()
        }

      case let .loadDXTFile(tempDir, manifest, manifestData):
        // Configure state for DXT file
        state.transport = .dxt
        state.serverName = manifest.displayName ?? manifest.name
        state.serverNameManuallyEdited = true
        state.dxtConfig.manifest = manifest
        state.dxtConfig.manifestData = manifestData
        state.dxtConfig.tempDirectory = tempDir

        return .send(.validateState)

      // Transport actions
      case let .stdioConfig(action):
        switch action {
        case .commandChanged:
          return .send(.validateState)
        case .arguments, .environmentVariables, .stdioTabChanged:
          return .none
        }

      case let .httpConfig(action):
        switch action {
        case let .urlChanged(url):
          // Auto-update server name if not manually edited or if it's empty
          if !state.serverNameManuallyEdited || state.serverName.isEmpty {
            if let extractedName = URLHelpers.extractHostName(from: url) {
              state.serverName = extractedName
              // Don't mark as manually edited since this was auto-generated
              state.serverNameManuallyEdited = false
            }
          }
          return .send(.validateState)

        case .headers, .setURLAutoUpdate:
          return .none
        }

      case let .dxtConfig(action):
        switch action {
        case let .fileProcessed(result):
          if case let .success((_, manifest, _)) = result {
            // Auto-populate server name if not manually edited
            if !state.serverNameManuallyEdited || state.serverName.isEmpty {
              state.serverName = manifest.displayName ?? manifest.name
              state.serverNameManuallyEdited = false
            }
          }
          return .send(.validateState)

        case .userConfigChanged:
          return .send(.validateState)

        case .fileSelected, .clearError:
          return .none
        }

      case .validateState:
        return .run {
          [
            serverName = state.serverName,
            mode = state.mode,
            transport = state.transport,
            transportConfig = state.transportConfig,
            serverStore
          ] send in
          // Determine which server ID to exclude for validation
          let excludingID: UUID? = {
            switch mode {
            case .add:
              return nil
            case .edit(let originalServer):
              return originalServer.id
            }
          }()

          let validationResult = try await serverStore.validateServerName(
            serverName,
            excludingServerID: excludingID
          )

          let serverNameError: String? = {
            switch validationResult {
            case .valid:
              return nil
            case .invalid(let reason):
              return reason
            }
          }()

          let validation = Self.validateState(
            serverName: serverName,
            serverNameError: serverNameError,
            transport: transport,
            transportConfig: transportConfig,
            mode: mode
          )

          await send(.setValidation(validation))
        }

      case let .setValidation(validation):
        state.validation = validation
        return .none
      }
    }
  }

  private func saveServer(state: State) -> Effect<Action> {
    // Generate ID based on mode
    let serverID: UUID
    switch state.mode {
    case .add:
      serverID = UUID()
    case .edit(let originalServer):
      serverID = originalServer.id
    }

    return .run {
      [
        serverID = serverID,
        mode = state.mode,
        serverName = state.serverName,
        transport = state.transport,
        transportConfig = state.transportConfig,
        dxtTempDirectory = state.dxtConfig.tempDirectory,
        hasDxtManifest = state.dxtConfig.manifest != nil,
        dxtUserConfigValues = state.dxtConfig.userConfig.values,
        serverStore = self.serverStore,
        dxtStore = self.dxtStore,
        dxtConfigKeychain = self.dxtConfigKeychain,
        logger = self.logger
      ] send in
      do {
        // Build the server using ServerStore
        var server = serverStore.buildServer(
          id: serverID,
          name: serverName,
          transport: transport,
          config: transportConfig
        )

        // For DXT, install the server first
        if transport == .dxt,
          let tempDir = dxtTempDirectory,
          hasDxtManifest
        {
          _ = try await dxtStore.installServer(
            from: tempDir,
            serverID: serverID,
            mode: mode
          )

          // Handle sensitive values in DXT user config
          if !dxtUserConfigValues.isEmpty {
            // Collect old keychain references to delete
            var keychainRefsToDelete: [UUID] = []

            // In edit mode, identify old keychain values that need cleanup
            if case .edit(let originalServer) = mode,
              let originalConfig = originalServer.dxtUserConfig
            {
              // Find old keychain references that are being replaced
              for (key, originalValue) in originalConfig.values {
                if case .keychainReference(let oldUuid) = originalValue.value {
                  // Check if this key is being replaced with a new value
                  if let newValue = dxtUserConfigValues[key],
                    case .keychainReference(let newUuid) = newValue.value,
                    newUuid == oldUuid
                  {
                    // Same reference, keep it
                    continue
                  } else {
                    // Different value or no longer exists, mark for deletion
                    keychainRefsToDelete.append(oldUuid)
                  }
                }
              }
            }

            // Replace sensitive values with keychain references
            let userConfig = DXTUserConfigurationValues(values: dxtUserConfigValues)

            do {
              let processedConfig = try await userConfig.replacingSensitiveValues { key, value in
                let uuid = UUID()
                try await dxtConfigKeychain.storeValue(value, for: uuid)
                return uuid
              }

              // Update server with processed config
              server.dxtUserConfig = processedConfig
            } catch {
              // If keychain storage fails, log the error but continue with plaintext values
              logger.error("Failed to store sensitive values in keychain: \(error)")
              logger.warning("Falling back to storing sensitive values as plaintext")
              server.dxtUserConfig = userConfig
            }

            // Clean up old keychain references after successful storage
            for uuid in keychainRefsToDelete {
              do {
                try await dxtConfigKeychain.deleteValue(for: uuid)
              } catch {
                logger.warning("Failed to delete old keychain reference \(uuid): \(error)")
              }
            }
          }
        }

        // Save to database using ServerStore
        switch mode {
        case .add:
          try await serverStore.createServer(server)
        case .edit:
          try await serverStore.updateServer(server)
        }

        await send(.serverSaved(.success(serverID)))
      } catch {
        await send(.serverSaved(.failure(error)))
      }
    }
  }

  // MARK: - Validation

  private static func validateState(
    serverName: String,
    serverNameError: String?,
    transport: TransportType,
    transportConfig: TransportConfig,
    mode: AddServerMode
  ) -> ValidationState {
    guard !serverName.isEmpty else {
      return .invalid
    }

    guard serverNameError == nil else {
      return ValidationState(serverNameError: serverNameError, isValid: false)
    }

    let isTransportValid: Bool
    switch (transport, transportConfig) {
    case (.stdio, .stdio(let config)):
      isTransportValid = !config.command.isEmpty
    case (.sse, .http(let config)), (.streamableHTTP, .http(let config)):
      isTransportValid = !config.url.isEmpty && URL(string: config.url) != nil
    case (.dxt, .dxt(let config)):
      // In edit mode, we don't require tempDirectory since we're editing an installed server
      let isEditMode = if case .edit = mode { true } else { false }

      if isEditMode {
        // For edit mode, only require manifest
        guard config.manifest != nil else {
          isTransportValid = false
          break
        }
      } else {
        // For add mode, require both manifest and tempDirectory
        guard config.manifest != nil && config.tempDirectory != nil else {
          isTransportValid = false
          break
        }
      }

      // Check if all required user config fields are filled
      if let manifest = config.manifest {
        isTransportValid = config.userConfig.missingRequiredKeys(from: manifest).isEmpty
      } else {
        isTransportValid = true
      }
    default:
      // Mismatched transport and config
      isTransportValid = false
    }

    return ValidationState(
      serverNameError: serverNameError,
      isValid: isTransportValid
    )
  }
}
