// Copyright © 2023 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Dependencies
import Foundation
import GRDB
import SharingGRDB

@Reducer
struct AddServerFeature {
  @ObservableState
  struct State: Equatable {
    enum Mode: Equatable {
      case add
      case edit(originalServer: MCPServer)
    }

    enum Screen: Equatable {
      case form
      case error(String)
    }

    struct Header: Equatable, Identifiable {
      let id = UUID()
      var key: String = ""
      var value: String = ""
      var shouldFocusKey: Bool = false
    }

    struct Argument: Equatable, Identifiable {
      let id = UUID()
      var value: String = ""
      var shouldFocus: Bool = false
    }

    struct EnvironmentVariable: Equatable, Identifiable {
      let id = UUID()
      var name: String = ""
      var value: String = ""
      var shouldFocusName: Bool = false
    }

    enum StdioTab: String, CaseIterable {
      case arguments = "Arguments"
      case environment = "Environment"
    }

    var mode: Mode = .add
    var screen: Screen = .form
    var serverName: String = ""
    var transport: TransportType = .streamableHTTP
    var serverNameManuallyEdited: Bool = false

    // Stdio fields
    var command: String = ""
    var arguments: [Argument] = []
    var selectedArgumentId: Argument.ID?
    var environmentVariables: [EnvironmentVariable] = []
    var selectedEnvironmentId: EnvironmentVariable.ID?
    var stdioTab: StdioTab = .arguments

    // URL-based fields
    var url: String = ""
    var headers: [Header] = []
    var selectedHeaderId: Header.ID?

    // Validation
    var existingServerNames: Set<String> = []
    var serverNameError: String? {
      guard !serverName.isEmpty else { return nil }

      // Check for duplicate names, but allow keeping the same name when editing
      switch mode {
      case .add:
        return existingServerNames.contains(serverName)
          ? "A server with this name already exists" : nil
      case .edit(let originalServer):
        // Allow keeping the same name when editing
        if serverName == originalServer.name {
          return nil
        }
        return existingServerNames.contains(serverName)
          ? "A server with this name already exists" : nil
      }
    }

    // Validation
    var isValid: Bool {
      guard !serverName.isEmpty else { return false }
      guard serverNameError == nil else { return false }

      switch transport {
      case .stdio:
        return !command.isEmpty
      case .sse, .streamableHTTP:
        return !url.isEmpty && URL(string: url) != nil
      }
    }

    var transportDisplayName: String {
      switch transport {
      case .stdio:
        return "stdio"
      case .sse:
        return "HTTP+SSE"
      case .streamableHTTP:
        return "Streamable HTTP"
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

      self.command = server.command ?? ""
      self.url = server.url ?? ""

      // Convert arguments array to Argument structs
      if let args = server.args {
        self.arguments = args.map { arg in
          Argument(value: arg)
        }
      }

      // Convert environment dictionary to EnvironmentVariable structs
      if let env = server.environment {
        self.environmentVariables = env.map { key, value in
          EnvironmentVariable(name: key, value: value)
        }
      }

      // Convert headers dictionary to Header structs
      if let headers = server.headers {
        self.headers = headers.map { key, value in
          Header(key: key, value: value)
        }
      }
    }
  }

  enum Action {
    case setExistingServerNames(Set<String>)
    case serverNameChanged(String)
    case transportChanged(TransportType)
    case commandChanged(String)
    case addArgument
    case removeSelectedArgument
    case argumentChanged(State.Argument.ID, String)
    case argumentFocusHandled(State.Argument.ID)
    case selectArgument(State.Argument.ID?)
    case stdioTabChanged(State.StdioTab)
    case addEnvironmentVariable
    case removeSelectedEnvironmentVariable
    case environmentNameChanged(State.EnvironmentVariable.ID, String)
    case environmentValueChanged(State.EnvironmentVariable.ID, String)
    case environmentFocusHandled(State.EnvironmentVariable.ID)
    case selectEnvironmentVariable(State.EnvironmentVariable.ID?)
    case urlChanged(String)
    case addHeader
    case removeSelectedHeader
    case headerKeyChanged(State.Header.ID, String)
    case headerValueChanged(State.Header.ID, String)
    case headerFocusHandled(State.Header.ID)
    case selectHeader(State.Header.ID?)
    case saveButtonTapped
    case serverSaved(Result<UUID, any Error>)
    case doneButtonTapped
    case cancelButtonTapped
  }

  @Dependency(\.dismiss) var dismiss
  @Dependency(\.defaultDatabase) var database

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .setExistingServerNames(names):
        state.existingServerNames = names
        return .none

      case let .serverNameChanged(name):
        state.serverName = name

        // Only mark as manually edited if the user actually typed something different
        // from what would be auto-generated
        if !name.isEmpty {
          // Check if this name is different from what would be auto-generated from current URL
          let autoGeneratedName = extractHostName(from: state.url) ?? ""
          if name != autoGeneratedName {
            state.serverNameManuallyEdited = true
          }
        } else {
          // If the name is cleared, allow auto-generation again
          state.serverNameManuallyEdited = false
        }

        return .none

      case let .transportChanged(transport):
        state.transport = transport
        return .none

      case let .commandChanged(command):
        state.command = command
        return .none

      case .addArgument:
        var newArgument = State.Argument()
        newArgument.value = "--arg"  // Start with a placeholder value like headers do
        newArgument.shouldFocus = true
        state.arguments.append(newArgument)
        state.selectedArgumentId = newArgument.id
        return .none

      case .removeSelectedArgument:
        if let selectedId = state.selectedArgumentId,
          let index = state.arguments.firstIndex(where: { $0.id == selectedId })
        {
          state.arguments.remove(at: index)
          state.selectedArgumentId = nil
        }
        return .none

      case let .argumentChanged(id, value):
        if let index = state.arguments.firstIndex(where: { $0.id == id }) {
          state.arguments[index].value = value
          // Only remove empty arguments if they're not being focused
          if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.arguments[index].shouldFocus
          {
            state.arguments.remove(at: index)
            if state.selectedArgumentId == id {
              state.selectedArgumentId = nil
            }
          }
        }
        return .none

      case let .argumentFocusHandled(id):
        if let index = state.arguments.firstIndex(where: { $0.id == id }) {
          state.arguments[index].shouldFocus = false
        }
        return .none

      case let .selectArgument(id):
        state.selectedArgumentId = id
        return .none

      case let .stdioTabChanged(tab):
        state.stdioTab = tab
        return .none

      case .addEnvironmentVariable:
        var newEnv = State.EnvironmentVariable()
        newEnv.name = "VAR_NAME"
        newEnv.shouldFocusName = true
        state.environmentVariables.append(newEnv)
        state.selectedEnvironmentId = newEnv.id
        return .none

      case .removeSelectedEnvironmentVariable:
        if let selectedId = state.selectedEnvironmentId,
          let index = state.environmentVariables.firstIndex(where: { $0.id == selectedId })
        {
          state.environmentVariables.remove(at: index)
          state.selectedEnvironmentId = nil
        }
        return .none

      case let .environmentNameChanged(id, name):
        if let index = state.environmentVariables.firstIndex(where: { $0.id == id }) {
          state.environmentVariables[index].name = name
          // Remove if both name and value are empty
          let env = state.environmentVariables[index]
          if env.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && env.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          {
            state.environmentVariables.remove(at: index)
            if state.selectedEnvironmentId == id {
              state.selectedEnvironmentId = nil
            }
          }
        }
        return .none

      case let .environmentValueChanged(id, value):
        if let index = state.environmentVariables.firstIndex(where: { $0.id == id }) {
          state.environmentVariables[index].value = value
          // Remove if both name and value are empty
          let env = state.environmentVariables[index]
          if env.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && env.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          {
            state.environmentVariables.remove(at: index)
            if state.selectedEnvironmentId == id {
              state.selectedEnvironmentId = nil
            }
          }
        }
        return .none

      case let .environmentFocusHandled(id):
        if let index = state.environmentVariables.firstIndex(where: { $0.id == id }) {
          state.environmentVariables[index].shouldFocusName = false
        }
        return .none

      case let .selectEnvironmentVariable(id):
        state.selectedEnvironmentId = id
        return .none

      case let .urlChanged(url):
        state.url = url

        // Auto-update server name if not manually edited or if it's empty
        if !state.serverNameManuallyEdited || state.serverName.isEmpty {
          if let extractedName = extractHostName(from: url) {
            state.serverName = extractedName
            // Don't mark as manually edited since this was auto-generated
            state.serverNameManuallyEdited = false
          }
        }

        return .none

      case .addHeader:
        var newHeader = State.Header(key: "Authorization", value: "")
        newHeader.shouldFocusKey = true
        state.headers.append(newHeader)
        state.selectedHeaderId = newHeader.id
        return .none

      case .removeSelectedHeader:
        if let selectedId = state.selectedHeaderId,
          let index = state.headers.firstIndex(where: { $0.id == selectedId })
        {
          state.headers.remove(at: index)
          state.selectedHeaderId = nil
        }
        return .none

      case let .headerKeyChanged(id, newKey):
        if let index = state.headers.firstIndex(where: { $0.id == id }) {
          state.headers[index].key = newKey
          // Remove header if both key and value are empty
          let header = state.headers[index]
          if header.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && header.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          {
            state.headers.remove(at: index)
            if state.selectedHeaderId == id {
              state.selectedHeaderId = nil
            }
          }
        }
        return .none

      case let .headerValueChanged(id, value):
        if let index = state.headers.firstIndex(where: { $0.id == id }) {
          state.headers[index].value = value
          // Remove header if both key and value are empty
          let header = state.headers[index]
          if header.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && header.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          {
            state.headers.remove(at: index)
            if state.selectedHeaderId == id {
              state.selectedHeaderId = nil
            }
          }
        }
        return .none

      case let .headerFocusHandled(id):
        if let index = state.headers.firstIndex(where: { $0.id == id }) {
          state.headers[index].shouldFocusKey = false
        }
        return .none

      case let .selectHeader(id):
        state.selectedHeaderId = id
        return .none

      case .saveButtonTapped:
        let server = createServer(from: state)

        return .run { [mode = state.mode, serverId = server.id] send in
          do {
            try await database.write { db in
              switch mode {
              case .add:
                try MCPServer.insert { server }.execute(db)
              case .edit:
                // Update the existing server (ID is already preserved in createServer)
                try MCPServer.update(server).execute(db)
              }
            }
            await send(.serverSaved(.success(serverId)))
          } catch {
            await send(.serverSaved(.failure(error)))
          }
        }

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
      }
    }
  }

  private func createServer(from state: State) -> MCPServer {
    let id: UUID
    switch state.mode {
    case .add:
      id = UUID()  // Generate new ID for new servers
    case .edit(let originalServer):
      id = originalServer.id  // Preserve existing ID for edits
    }

    // Always use streamableHTTP instead of deprecated .sse
    var transport = state.transport
    if state.transport == .streamableHTTP || state.transport == .sse {
      transport = .streamableHTTP
    }

    var server = MCPServer(
      id: id,
      name: state.serverName,
      transport: transport
    )

    switch state.transport {
    case .stdio:
      server.command = state.command
      let filteredArgs = state.arguments.map { $0.value }.filter { !$0.isEmpty }
      server.args = filteredArgs.isEmpty ? nil : filteredArgs
      let validEnv = state.environmentVariables.filter { !$0.name.isEmpty && !$0.value.isEmpty }
      let envDict = Dictionary(uniqueKeysWithValues: validEnv.map { ($0.name, $0.value) })
      server.environment = envDict.isEmpty ? nil : envDict

    case .sse, .streamableHTTP:
      server.url = state.url
      let validHeaders = state.headers.filter { !$0.key.isEmpty && !$0.value.isEmpty }
      let headerDict = Dictionary(uniqueKeysWithValues: validHeaders.map { ($0.key, $0.value) })
      server.headers = headerDict.isEmpty ? nil : headerDict
    }

    return server
  }

  private func extractHostName(from urlString: String) -> String? {
    // Use URLComponents for more robust URL parsing
    guard let urlComponents = URLComponents(string: urlString),
      let host = urlComponents.host
    else {
      return nil
    }

    // Remove common subdomains and TLDs to extract the main domain name
    let components = host.components(separatedBy: ".")

    // Handle cases like "example.com" or "sub.example.com" or "example.co.uk"
    if components.count >= 2 {
      // Find the main domain part (usually the second-to-last component before TLD)
      // For simplicity, we'll take the component before the last dot(s)
      // This handles most common cases
      if components.count == 2 {
        // Simple case: example.com -> example
        return components[0]
      } else {
        // More complex case: Try to identify the main domain
        // Common TLDs and second-level domains
        let commonTLDs = ["com", "net", "org", "io", "dev", "app", "co", "gov", "edu", "mil"]

        // Check if second-to-last is a common TLD (like .co in .co.uk)
        if components.count >= 3 && commonTLDs.contains(components[components.count - 2]) {
          // Case like example.co.uk -> example
          return components[components.count - 3]
        } else {
          // Case like sub.example.com -> example
          return components[components.count - 2]
        }
      }
    }

    // Fallback: return the whole host without port
    return host
  }
}
