// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Foundation

@Reducer
struct KeyValueListFeature {

  struct Item: Equatable, Identifiable {
    let id = UUID()
    var key: String
    var value: String
    var shouldFocusKey: Bool = false

    init(key: String = "", value: String = "", shouldFocusKey: Bool = false) {
      self.key = key
      self.value = value
      self.shouldFocusKey = shouldFocusKey
    }
  }

  struct Placeholder: Equatable {
    let key: String
    let value: String

    init(key: String = "Key", value: String = "Value") {
      self.key = key
      self.value = value
    }
  }

  @ObservableState
  struct State: Equatable {
    var items: [Item] = []
    var selectedId: Item.ID?
    var placeholder: Placeholder

    init(
      items: [Item] = [],
      selectedId: Item.ID? = nil,
      placeholder: Placeholder = Placeholder()
    ) {
      self.items = items
      self.selectedId = selectedId
      self.placeholder = placeholder
    }
  }

  enum Action {
    case addItem
    case removeSelected
    case itemKeyChanged(Item.ID, String)
    case itemValueChanged(Item.ID, String)
    case selectItem(Item.ID?)
    case focusHandled(Item.ID)
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .addItem:
        let newItem = Item(
          key: state.placeholder.key, value: state.placeholder.value, shouldFocusKey: true)
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

      case let .itemKeyChanged(id, newKey):
        if let index = state.items.firstIndex(where: { $0.id == id }) {
          state.items[index].key = newKey
          // Remove item if both key and value are empty
          let item = state.items[index]
          if item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          {
            state.items.remove(at: index)
            if state.selectedId == id {
              state.selectedId = nil
            }
          }
        }
        return .none

      case let .itemValueChanged(id, newValue):
        if let index = state.items.firstIndex(where: { $0.id == id }) {
          state.items[index].value = newValue
          // Remove item if both key and value are empty
          let item = state.items[index]
          if item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
          state.items[index].shouldFocusKey = false
        }
        return .none
      }
    }
  }
}
