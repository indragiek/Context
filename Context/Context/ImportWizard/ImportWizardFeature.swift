// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Dependencies
import Foundation
import GRDB
import SharingGRDB

// Global array of all available MCP server importers
let allMCPServerImporters: [any MCPServerImporter.Type] = [
  ClaudeDesktopMCPServerImporter.self,
  ClaudeCodeMCPServerImporter.self,
  CursorMCPServerImporter.self,
  WindsurfMCPServerImporter.self,
  VSCodeMCPServerImporter.self,
]

@Reducer
struct ImportWizardFeature {
  @ObservableState
  struct State: Equatable {
    enum Screen: Equatable {
      case directorySelection
      case loadingSources
      case sourceSelection
      case importing
      case complete(importedCount: Int, updatedCount: Int)
      case error(String)
    }

    struct ImportSource: Equatable, Identifiable {
      let id = UUID()
      let name: String
      let importerType: any MCPServerImporter.Type
      let configurationURLs: [URL]
      var isSelected: Bool = true
      var servers: IdentifiedArrayOf<ServerSelection> = []
      var isLoading: Bool = false
      var loadError: String?

      static func == (lhs: ImportSource, rhs: ImportSource) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
          && lhs.importerType.identifier == rhs.importerType.identifier
          && lhs.configurationURLs == rhs.configurationURLs && lhs.isSelected == rhs.isSelected
          && lhs.servers == rhs.servers && lhs.isLoading == rhs.isLoading
          && lhs.loadError == rhs.loadError
      }
    }

    struct ServerSelection: Equatable, Identifiable {
      let id = UUID()
      let server: MCPServer
      var isSelected: Bool = true
    }

    var screen: Screen = .directorySelection
    var sources: IdentifiedArrayOf<ImportSource> = []
    var selectedSource: ImportSource?
    var projectDirectories: [URL] = []
    var hasHomeAccess: Bool = false
    var homeURL: URL? = nil
    var securityScopedURLs: Set<URL> = []

    var canProceedFromDirectorySelection: Bool {
      !projectDirectories.isEmpty || hasHomeAccess
    }

    var hasValidSelection: Bool {
      sources.contains { source in
        source.isSelected && source.servers.contains { $0.isSelected }
      }
    }

    var selectedServers: [MCPServer] {
      sources.flatMap { source -> [MCPServer] in
        guard source.isSelected else { return [] }
        return source.servers.compactMap { selection in
          selection.isSelected ? selection.server : nil
        }
      }
    }
  }

  enum Action {
    case onAppear
    case addProjectDirectoryTapped
    case projectDirectorySelected(URL)
    case removeProjectDirectory(URL)
    case selectHomeFolderTapped
    case homeFolderSelected(URL)
    case directorySelectionNextTapped
    case sourceSelected(State.ImportSource.ID)
    case toggleSourceSelection(State.ImportSource.ID)
    case toggleServerSelection(
      sourceID: State.ImportSource.ID,
      serverID: State.ServerSelection.ID)
    case loadServersForSource(State.ImportSource.ID)
    case serversLoadedForSource(
      State.ImportSource.ID, Result<[MCPServer], any Error>)
    case nextButtonTapped
    case backToDirectorySelection
    case importServers
    case importCompleted(Result<(new: Int, updated: Int), any Error>)
    case allSourcesLoaded
    case doneButtonTapped
    case cancelButtonTapped
  }

  @Dependency(\.dismiss) var dismiss
  @Dependency(\.defaultDatabase) var database

  var body: some ReducerOf<Self> {
    Reduce {
      state,
      action in
      switch action {
      case .onAppear:
        state.homeURL = getUserHomeDirectoryURLFromPasswd()
        return .none

      case .addProjectDirectoryTapped:
        return .none

      case let .projectDirectorySelected(url):
        if !state.projectDirectories.contains(url) {
          if url.startAccessingSecurityScopedResource() {
            state.securityScopedURLs.insert(url)
          }
          state.projectDirectories.append(url)
        }
        return .none

      case let .removeProjectDirectory(url):
        state.projectDirectories.removeAll { $0 == url }
        if state.securityScopedURLs.contains(url) {
          url.stopAccessingSecurityScopedResource()
          state.securityScopedURLs.remove(url)
        }
        return .none

      case .selectHomeFolderTapped:
        return .none

      case let .homeFolderSelected(url):
        let standardizedSelectedPath = url.standardizedFileURL.path
        let expectedHomePath = getUserHomeDirectoryURLFromPasswd()?.standardizedFileURL.path ?? ""

        if standardizedSelectedPath == expectedHomePath {
          if url.startAccessingSecurityScopedResource() {
            state.securityScopedURLs.insert(url)
          }
          state.hasHomeAccess = true
          state.homeURL = url
        }
        return .none

      case .directorySelectionNextTapped:
        state.screen = .loadingSources

        state.sources = []

        let projectDirs = state.projectDirectories

        for importerType in allMCPServerImporters {
          let urls = importerType.configurationFileURLs(projectDirectoryURLs: projectDirs)
          let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }

          if !existingURLs.isEmpty {
            state.sources.append(
              State.ImportSource(
                name: importerType.name,
                importerType: importerType,
                configurationURLs: existingURLs
              ))
          }
        }

        guard !state.sources.isEmpty else {
          state.screen = .error(
            "No MCP server configuration files found in the selected directories.")
          return .none
        }

        return .run { [sources = state.sources] send in
          for source in sources {
            await send(.loadServersForSource(source.id))
          }
        }

      case let .sourceSelected(id):
        guard let source = state.sources[id: id] else { return .none }
        state.selectedSource = source
        return .none

      case let .toggleSourceSelection(id):
        guard let source = state.sources[id: id] else { return .none }
        let newValue = !source.isSelected
        state.sources[id: id]?.isSelected = newValue

        if !newValue {
          for server in source.servers {
            state.sources[id: id]?.servers[id: server.id]?.isSelected = false
          }
        }

        return .none

      case let .toggleServerSelection(sourceID, serverID):
        guard let source = state.sources[id: sourceID],
          let server = source.servers[id: serverID]
        else { return .none }

        let newValue = !server.isSelected
        state.sources[id: sourceID]?.servers[id: serverID]?.isSelected = newValue

        if newValue && !source.isSelected {
          state.sources[id: sourceID]?.isSelected = true
        }

        return .none

      case let .loadServersForSource(id):
        state.sources[id: id]?.isLoading = true
        state.sources[id: id]?.loadError = nil

        return .run {
          [source = state.sources[id: id], projectDirs = state.projectDirectories] send in
          guard let source else { return }

          do {
            let importer = source.importerType.init()
            let servers = try await importer.importServers(projectDirectoryURLs: projectDirs)
            await send(.serversLoadedForSource(id, .success(servers)))
          } catch {
            await send(.serversLoadedForSource(id, .failure(error)))
          }
        }

      case let .serversLoadedForSource(id, result):
        state.sources[id: id]?.isLoading = false

        switch result {
        case let .success(servers):
          state.sources[id: id]?.servers = IdentifiedArrayOf(
            uniqueElements: servers.map { State.ServerSelection(server: $0) })
        case let .failure(error):
          state.sources[id: id]?.loadError = error.localizedDescription
        }

        let allSourcesLoaded = state.sources.allSatisfy { source in
          !source.isLoading
        }

        if allSourcesLoaded {
          return .send(.allSourcesLoaded)
        }

        return .none

      case .nextButtonTapped:
        state.screen = .importing
        return .send(.importServers)

      case .backToDirectorySelection:
        state.screen = .directorySelection
        state.sources = []
        state.selectedSource = nil
        return .none

      case .importServers:
        var serversBySource: [(sourceIdentifier: String, servers: [MCPServer])] = []

        for source in state.sources where source.isSelected {
          let selectedServers = source.servers.compactMap { selection in
            selection.isSelected ? selection.server : nil
          }
          if !selectedServers.isEmpty {
            serversBySource.append((source.importerType.identifier, selectedServers))
          }
        }

        var allServers: [MCPServer] = []
        var globalNameCounts: [String: Int] = [:]

        for (sourceIdentifier, servers) in serversBySource {
          var sourceNameCounts: [String: Int] = [:]

          for server in servers {
            var baseName = server.name

            let globalCount = globalNameCounts[server.name] ?? 0
            if globalCount > 0 {
              baseName = "\(sourceIdentifier).\(server.name)"
            }

            let sourceCount = sourceNameCounts[baseName] ?? 0
            var finalName = baseName

            if sourceCount > 0 {
              finalName = "\(baseName) (\(sourceCount + 1))"
            }

            globalNameCounts[server.name] = globalCount + 1
            sourceNameCounts[baseName] = sourceCount + 1

            var updatedServer = server
            updatedServer.name = finalName
            allServers.append(updatedServer)
          }
        }

        return .run { [servers = allServers] send in
          do {
            let existingServers = try await database.read { db in
              try MCPServer.all.fetchAll(db)
            }

            let existingServerNames = Set(existingServers.map { $0.name })
            let updatedServers = servers.compactMap {
              existingServerNames.contains($0.name) ? MCPServer.Draft($0) : nil
            }
            let newServers = servers.compactMap {
              existingServerNames.contains($0.name) ? nil : $0
            }

            try await database.write { db in
              for draft in updatedServers {
                try MCPServer.upsert { draft }.execute(db)
              }
              try MCPServer.insert { newServers }.execute(db)
            }

            await send(
              .importCompleted(.success((new: newServers.count, updated: updatedServers.count)))
            )
          } catch {
            await send(.importCompleted(.failure(error)))
          }
        }

      case let .importCompleted(result):
        switch result {
        case let .success(counts):
          state.screen = .complete(importedCount: counts.new, updatedCount: counts.updated)
        case let .failure(error):
          state.screen = .error(error.localizedDescription)
        }
        return .none

      case .allSourcesLoaded:
        state.sources.removeAll { source in
          source.loadError != nil || source.servers.isEmpty
        }

        if state.sources.isEmpty {
          state.screen = .error(
            "No MCP servers found in the selected directories. Please ensure you have MCP server configurations in the selected locations."
          )
        } else {
          state.screen = .sourceSelection

          if let firstSource = state.sources.first {
            state.selectedSource = firstSource
          }
        }

        return .none

      case .doneButtonTapped:
        for url in state.securityScopedURLs {
          url.stopAccessingSecurityScopedResource()
        }
        state.securityScopedURLs.removeAll()

        return .run { _ in
          await dismiss()
        }

      case .cancelButtonTapped:
        for url in state.securityScopedURLs {
          url.stopAccessingSecurityScopedResource()
        }
        state.securityScopedURLs.removeAll()

        return .run { _ in
          await dismiss()
        }
      }
    }
  }
}
