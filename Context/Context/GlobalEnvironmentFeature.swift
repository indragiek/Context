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

    enum Field {
      case key
      case value
    }
  }

  @Dependency(\.defaultDatabase) var database

  enum CancelID {
    case saveDebounce
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        state.isLoading = true
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
      }
    }
  }
}

