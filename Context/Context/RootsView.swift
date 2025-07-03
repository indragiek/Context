// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct RootsView: View {
  let store: StoreOf<RootsFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(alignment: .leading, spacing: 16) {
        // Explanatory text
        Text(
          "A root is a URI that a client suggests a server should focus on. When a client connects to a server, it declares which roots the server should work with. While primarily used for filesystem paths, roots can be any valid URI including HTTP URLs."
        )
        .font(.body)
        .foregroundColor(.secondary)

        // Table with roots
        VStack(spacing: 0) {
          if viewStore.roots.isEmpty {
            VStack(spacing: 8) {
              Text("No roots configured")
                .font(.caption)
                .foregroundColor(.secondary)
              Text("Click + to add a root")
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: 150)
          } else {
            Table(
              viewStore.roots,
              selection: viewStore.binding(
                get: \.selectedId,
                send: RootsFeature.Action.selectRoot
              )
            ) {
              TableColumn("Name") { item in
                FocusedTextField(
                  placeholder: "Root name",
                  text: Binding(
                    get: { item.name },
                    set: { store.send(.nameChanged(item.id, $0)) }
                  ),
                  shouldFocus: item.shouldFocusName,
                  onFocusHandled: {
                    store.send(.focusHandled(item.id, field: .name))
                  }
                )
                .onSubmit {
                  store.send(.save)
                }
              }
              .width(150)

              TableColumn("URI") { item in
                FocusedTextField(
                  placeholder: "file:///path/to/folder or https://example.com",
                  text: Binding(
                    get: { item.uri },
                    set: { store.send(.uriChanged(item.id, $0)) }
                  ),
                  shouldFocus: item.shouldFocusURI,
                  onFocusHandled: {
                    store.send(.focusHandled(item.id, field: .uri))
                  }
                )
                .onSubmit {
                  store.send(.save)
                }
                .overlay(alignment: .trailing) {
                  if let error = validateURI(item.uri), !item.uri.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                      .foregroundColor(.red)
                      .help(error)
                      .padding(.trailing, 8)
                  }
                }
              }
            }
            .alternatingRowBackgrounds(.disabled)
            .onDeleteCommand {
              store.send(.removeSelected)
            }
          }

          HStack(spacing: 0) {
            Button(action: {
              store.send(.addRoot)
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

        if viewStore.isLoading {
          ProgressView()
            .scaleEffect(0.8)
        }
        
        Spacer()
      }
      .padding(20)
      .alert(
        "Error",
        isPresented: viewStore.binding(
          get: { $0.errorMessage != nil },
          send: { _ in .errorDismissed }
        )
      ) {
        Button("OK") { store.send(.errorDismissed) }
      } message: {
        if let error = viewStore.errorMessage {
          Text(error)
        }
      }
      .task {
        store.send(.task)
      }
    }
  }

  private func validateURI(_ uri: String) -> String? {
    guard !uri.isEmpty else { return nil }

    guard let url = URL(string: uri) else {
      return "Invalid URL format"
    }

    // Check if it's a file URL and validate the path exists
    if url.scheme == "file" {
      let path = url.path
      if !FileManager.default.fileExists(atPath: path) {
        return "Path does not exist: \(path)"
      }
    }

    return nil
  }
}
