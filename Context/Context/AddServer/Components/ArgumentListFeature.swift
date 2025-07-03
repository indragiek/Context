// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Foundation

struct ArgumentItem: Equatable, Identifiable {
  let id = UUID()
  var value: String = ""
  var shouldFocus: Bool = false
}

@Reducer
struct ArgumentListFeature {

  struct Item: Equatable, Identifiable {
    let id = UUID()
    var value: String
    var shouldFocus: Bool = false

    init(value: String = "", shouldFocus: Bool = false) {
      self.value = value
      self.shouldFocus = shouldFocus
    }
  }

  @ObservableState
  struct State: Equatable {
    var items: [Item] = []
    var selectedId: Item.ID?
    var placeholder: String

    init(
      items: [Item] = [],
      selectedId: Item.ID? = nil,
      placeholder: String = "--arg"
    ) {
      self.items = items
      self.selectedId = selectedId
      self.placeholder = placeholder
    }
  }

  enum Action {
    case addItem
    case removeSelected
    case itemChanged(Item.ID, String)
    case selectItem(Item.ID?)
    case focusHandled(Item.ID)
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .addItem:
        let newItem = Item(value: state.placeholder, shouldFocus: true)
        state.items.append(newItem)
        state.selectedId = newItem.id
        return .none

      case .removeSelected:
        if let selectedId = state.selectedId,
          let index = state.items.firstIndex(where: { $0.id == selectedId })
        {
          state.items.remove(at: index)
          state.selectedId = nil
        }
        return .none

      case let .itemChanged(id, value):
        if let index = state.items.firstIndex(where: { $0.id == id }) {
          state.items[index].value = value
          // Only remove empty arguments if they're not being focused
          if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.items[index].shouldFocus
          {
            state.items.remove(at: index)
            if state.selectedId == id {
              state.selectedId = nil
            }
          }
        }
        return .none

      case let .selectItem(id):
        state.selectedId = id
        return .none

      case let .focusHandled(id):
        if let index = state.items.firstIndex(where: { $0.id == id }) {
          state.items[index].shouldFocus = false
        }
        return .none
      }
    }
  }
}
