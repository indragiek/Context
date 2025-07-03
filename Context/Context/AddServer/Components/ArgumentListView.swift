// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct ArgumentListView: View {
  let store: StoreOf<ArgumentListFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in

      VStack(spacing: 0) {
        if viewStore.items.isEmpty {
          VStack(spacing: 8) {
            Text("No arguments")
              .font(.caption)
              .foregroundColor(.secondary)
            Text("Click + to add command line arguments")
              .font(.caption)
              .foregroundColor(Color.secondary.opacity(0.5))
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .frame(height: 120)
        } else {
          Table(
            viewStore.items,
            selection: viewStore.binding(
              get: \.selectedId,
              send: ArgumentListFeature.Action.selectItem
            )
          ) {
            TableColumn("Argument") { item in
              FocusedTextField(
                placeholder: "",
                text: Binding(
                  get: { item.value },
                  set: { store.send(.itemChanged(item.id, $0)) }
                ),
                shouldFocus: item.shouldFocus,
                onFocusHandled: {
                  store.send(.focusHandled(item.id))
                }
              )
            }
          }
          .frame(height: 120)
          .alternatingRowBackgrounds(.disabled)
          .onDeleteCommand {
            store.send(.removeSelected)
          }
        }

        HStack(spacing: 0) {
          Button(action: {
            store.send(.addItem)
          }) {
            Image(systemName: "plus")
              .frame(width: 20, height: 20)
          }
          .buttonStyle(.borderless)

          Button(action: { store.send(.removeSelected) }) {
            Image(systemName: "minus")
              .frame(width: 20, height: 20)
          }
          .buttonStyle(.borderless)
          .disabled(viewStore.selectedId == nil)

          Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color(NSColor.controlBackgroundColor))
      }
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
      )
    }
  }
}
