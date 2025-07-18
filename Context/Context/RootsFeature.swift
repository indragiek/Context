// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import ComposableArchitecture
import Foundation
import SharingGRDB

struct RootItem: Equatable, Identifiable {
  let id: UUID
  var name: String
  var uri: String
  var shouldFocusName: Bool = false
  var shouldFocusURI: Bool = false
}

@Reducer
struct RootsFeature {
  @ObservableState
  struct State: Equatable {
    var roots: [RootItem] = []
    var selectedId: RootItem.ID?
    var errorMessage: String?
    var isLoading = false
  }

  enum Action {
    case task
    case rootsLoaded([MCPRoot])
    case addRoot
    case removeSelected
    case nameChanged(RootItem.ID, String)
    case uriChanged(RootItem.ID, String)
    case selectRoot(RootItem.ID?)
    case focusHandled(RootItem.ID, field: Field)
    case save
    case saved(Result<Void, any Error>)
    case errorDismissed
    case browseButtonTapped(RootItem.ID)

    enum Field {
      case name
      case uri
    }
  }

  @Dependency(\.defaultDatabase) var database
  @Dependency(\.mcpClientManager) var clientManager
  
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
            let roots = try await database.read { db in
              try MCPRoot.all.fetchAll(db)
            }
            await send(.rootsLoaded(roots))
          } catch {
            await send(.saved(.failure(error)))
          }
        }

      case let .rootsLoaded(roots):
        state.isLoading = false
        state.roots = roots.map { root in
          RootItem(id: root.id, name: root.name, uri: root.uri)
        }
        return .none

      case .addRoot:
        let newItem = RootItem(
          id: UUID(),
          name: "Root \(state.roots.count + 1)",
          uri: "",
          shouldFocusName: true,
          shouldFocusURI: false
        )
        state.roots.append(newItem)
        state.selectedId = newItem.id
        return .none

      case .removeSelected:
        if let selectedId = state.selectedId,
          let index = state.roots.firstIndex(where: { $0.id == selectedId })
        {
          state.roots.remove(at: index)
          state.selectedId = nil
          return .send(.save)
        }
        return .none

      case let .nameChanged(id, name):
        if let index = state.roots.firstIndex(where: { $0.id == id }) {
          state.roots[index].name = name
        }
        return .none

      case let .uriChanged(id, uri):
        if let index = state.roots.firstIndex(where: { $0.id == id }) {
          state.roots[index].uri = uri
        }
        return .none

      case let .selectRoot(id):
        state.selectedId = id
        return .none

      case let .focusHandled(id, field):
        if let index = state.roots.firstIndex(where: { $0.id == id }) {
          switch field {
          case .name:
            state.roots[index].shouldFocusName = false
          case .uri:
            state.roots[index].shouldFocusURI = false
          }
        }
        return .none

      case .save:
        let roots = state.roots
        return .run { send in
          do {
            let mcpRoots = roots.map { MCPRoot(id: $0.id, name: $0.name, uri: $0.uri) }
            try await database.write { db in
              try MCPRoot.delete().execute(db)
              try MCPRoot.insert { mcpRoots }.execute(db)
            }

            await clientManager.setRootsForAllClients(mcpRoots)
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
        
      case let .browseButtonTapped(id):
        return .run { send in
          await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select a file or directory for the root"

            if panel.runModal() == .OK, let url = panel.url {
              let fileURI = url.absoluteString
              send(.uriChanged(id, fileURI))
              send(.save)
            }
          }
        }
      }
    }
  }
}
