// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Foundation
import SharingGRDB

struct GlobalEnvironmentVariableItem: Equatable, Identifiable {
  let id: UUID
  var key: String
  var value: String
  var shouldFocusKey: Bool = false
  var shouldFocusValue: Bool = false
}

@Reducer
struct GlobalEnvironmentFeature {
  @ObservableState
  struct State: Equatable {
    var environmentVariables: [GlobalEnvironmentVariableItem] = []
    var selectedId: GlobalEnvironmentVariableItem.ID?
    var errorMessage: String?
    var isLoading = false
    
    // Shell configuration
    var shellSelection: ShellSelection = .loginShell
    var shellPath: String = ""
    var shellPathError: String?
    var showImportSuccess = false
    
    enum ShellSelection: Equatable {
      case loginShell
      case custom
    }
  }

  enum Action {
    case task
    case variablesLoaded([GlobalEnvironmentVariable])
    case addVariable
    case removeSelected
    case keyChanged(GlobalEnvironmentVariableItem.ID, String)
    case valueChanged(GlobalEnvironmentVariableItem.ID, String)
    case selectVariable(GlobalEnvironmentVariableItem.ID?)
    case focusHandled(GlobalEnvironmentVariableItem.ID, field: Field)
    case save
    case saved(Result<Void, any Error>)
    case errorDismissed
    
    // Shell configuration actions
    case shellSelectionChanged(State.ShellSelection)
    case shellPathChanged(String)
    case validateShellPath
    case shellPathValidated(String?)
    case importShellFrom(TerminalApp)
    case shellImported
    case dismissImportSuccess
    case saveShellConfiguration

    enum Field {
      case key
      case value
    }
  }

  @Dependency(\.defaultDatabase) var database

  enum CancelID {
    case saveDebounce
    case shellPathValidation
    case importSuccessDismissal
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        state.isLoading = true
        // Load shell configuration
        state.shellSelection = GlobalEnvironmentHelper.isUsingCustomShell() ? .custom : .loginShell
        state.shellPath = GlobalEnvironmentHelper.readShellPath()
        
        return .run { send in
          do {
            let variables = try await database.read { db in
              try GlobalEnvironmentVariable.all.fetchAll(db)
            }
            await send(.variablesLoaded(variables))
          } catch {
            await send(.saved(.failure(error)))
          }
        }

      case let .variablesLoaded(variables):
        state.isLoading = false
        state.environmentVariables = variables.map { variable in
          GlobalEnvironmentVariableItem(id: variable.id, key: variable.key, value: variable.value)
        }
        return .none

      case .addVariable:
        let newItem = GlobalEnvironmentVariableItem(
          id: UUID(),
          key: "",
          value: "",
          shouldFocusKey: true,
          shouldFocusValue: false
        )
        state.environmentVariables.append(newItem)
        state.selectedId = newItem.id
        return .none

      case .removeSelected:
        if let selectedId = state.selectedId,
          let index = state.environmentVariables.firstIndex(where: { $0.id == selectedId })
        {
          state.environmentVariables.remove(at: index)
          state.selectedId = nil
          return .send(.save)
        }
        return .none

      case let .keyChanged(id, key):
        if let index = state.environmentVariables.firstIndex(where: { $0.id == id }) {
          // Only allow valid environment variable names (alphanumeric and underscore, not starting with digit)
          let validKey = key.replacingOccurrences(
            of: #"[^a-zA-Z0-9_]"#,
            with: "",
            options: .regularExpression
          )
          state.environmentVariables[index].key = validKey
        }
        return .none

      case let .valueChanged(id, value):
        if let index = state.environmentVariables.firstIndex(where: { $0.id == id }) {
          state.environmentVariables[index].value = value
        }
        return .none

      case let .selectVariable(id):
        state.selectedId = id
        return .none

      case let .focusHandled(id, field):
        if let index = state.environmentVariables.firstIndex(where: { $0.id == id }) {
          switch field {
          case .key:
            state.environmentVariables[index].shouldFocusKey = false
          case .value:
            state.environmentVariables[index].shouldFocusValue = false
          }
        }
        return .none

      case .save:
        let variables = state.environmentVariables
        return .run { send in
          do {
            let globalVars = variables.map {
              GlobalEnvironmentVariable(id: $0.id, key: $0.key, value: $0.value)
            }
            try await database.write { db in
              try GlobalEnvironmentVariable.delete().execute(db)
              try GlobalEnvironmentVariable.insert { globalVars }.execute(db)
            }

            await send(.saved(.success(())))
          } catch {
            await send(.saved(.failure(error)))
          }
        }
        .debounce(id: CancelID.saveDebounce, for: .milliseconds(500), scheduler: DispatchQueue.main)

      case .saved(.success):
        state.errorMessage = nil
        return .none

      case let .saved(.failure(error)):
        state.errorMessage = error.localizedDescription
        return .none

      case .errorDismissed:
        state.errorMessage = nil
        return .none
        
      // Shell configuration actions
      case let .shellSelectionChanged(selection):
        state.shellSelection = selection
        state.shellPathError = nil
        return .send(.saveShellConfiguration)
        
      case let .shellPathChanged(path):
        state.shellPath = path
        return .send(.validateShellPath)
        
      case .validateShellPath:
        guard state.shellSelection == .custom else { return .none }
        
        // Clear error immediately if path is empty
        if state.shellPath.isEmpty {
          state.shellPathError = nil
          return .none
        }
        
        let path = state.shellPath
        return .run { send in
          try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second debounce
          
          var error: String?
          if !FileManager.default.fileExists(atPath: path) {
            error = "File does not exist"
          } else if !FileManager.default.isExecutableFile(atPath: path) {
            error = "File is not executable"
          }
          
          await send(.shellPathValidated(error))
        }
        .cancellable(id: CancelID.shellPathValidation)
        
      case let .shellPathValidated(error):
        state.shellPathError = error
        return .none
        
      case let .importShellFrom(terminal):
        let importedShell = terminal.readShellPath() ?? GlobalEnvironmentHelper.readShellPath()
        
        state.shellPath = importedShell
        state.shellPathError = nil
        state.showImportSuccess = true
        
        return .run { send in
          try? GlobalEnvironmentHelper.writeShellPath(importedShell)
          await send(.shellImported)
          
          try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
          await send(.dismissImportSuccess)
        }
        .cancellable(id: CancelID.importSuccessDismissal)
        
      case .shellImported:
        return .none
        
      case .dismissImportSuccess:
        state.showImportSuccess = false
        return .none
        
      case .saveShellConfiguration:
        do {
          if state.shellSelection == .custom {
            try GlobalEnvironmentHelper.writeShellPath(state.shellPath)
          } else {
            try GlobalEnvironmentHelper.writeShellPath(nil)
          }
          state.shellPathError = nil
        } catch {
          state.shellPathError = error.localizedDescription
        }
        return .none
      }
    }
  }
}

