// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct RootsView: View {
  let store: StoreOf<RootsFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(alignment: .leading, spacing: 16) {
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
                  },
                  onEditingChanged: { editing in
                    if !editing {
                      store.send(.save)
                    }
                  }
                )
                .onSubmit {
                  store.send(.save)
                }
              }
              .width(150)

              TableColumn("URI") { item in
                HStack(spacing: 4) {
                  FocusedTextField(
                    placeholder: "file:///path/to/folder or https://example.com",
                    text: Binding(
                      get: { item.uri },
                      set: { store.send(.uriChanged(item.id, $0)) }
                    ),
                    shouldFocus: item.shouldFocusURI,
                    onFocusHandled: {
                      store.send(.focusHandled(item.id, field: .uri))
                    },
                    onEditingChanged: { editing in
                      if !editing {
                        store.send(.save)
                      }
                    }
                  )
                  .onSubmit {
                    store.send(.save)
                  }
                  .overlay(alignment: .trailing) {
                    if let error = validateURI(item.uri), !item.uri.isEmpty {
                      ErrorIndicator(
                        error: error,
                        isSelected: viewStore.selectedId == item.id
                      )
                      .padding(.trailing, 8)
                    }
                  }
                  
                  if viewStore.selectedId == item.id {
                    Button("Browse...") {
                      store.send(.browseButtonTapped(item.id))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        
        // Explanatory text
        Text(
          "A root is a URI that a client suggests a server should focus on. When a client connects to a server, it declares which roots the server should work with. While primarily used for filesystem paths, roots can be any valid URI including HTTP URLs."
        )
        .font(.footnote)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

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
      .onDisappear {
        store.send(.save)
      }
    }
  }

  private func validateURI(_ uri: String) -> String? {
    guard !uri.isEmpty else { return nil }

    guard let url = URL(string: uri) else {
      return "Invalid URL format"
    }
    
    // Check if URL has a scheme
    guard let scheme = url.scheme, !scheme.isEmpty else {
      return "URL must have a scheme (e.g., file://, https://)"
    }

    // Check if it's a file URL and validate the path exists
    if scheme.lowercased() == "file" {
      let path = url.path
      if path.isEmpty {
        return "File URL must specify a path"
      }
      if !FileManager.default.fileExists(atPath: path) {
        return "Path does not exist: \(path)"
      }
    } else {
      // For non-file URLs, check if they have a host
      if url.host == nil || url.host?.isEmpty == true {
        return "URL must specify a host"
      }
    }

    return nil
  }
}

struct ErrorIndicator: View {
  let error: String
  let isSelected: Bool
  @State private var showPopover = false
  
  var body: some View {
    Button(action: {
      showPopover = true
    }) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundColor(isSelected ? .white : .red)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $showPopover, arrowEdge: .trailing) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.red)
          Text("Invalid URI")
            .font(.headline)
        }
        
        Text(error)
          .font(.body)
          .lineLimit(nil)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding()
      .frame(width: 300)
      .fixedSize(horizontal: true, vertical: false)
    }
  }
}
