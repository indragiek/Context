// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct GlobalEnvironmentView: View {
  let store: StoreOf<GlobalEnvironmentFeature>
  @State private var useCustomShell = GlobalEnvironmentHelper.isUsingCustomShell()
  @State private var shellPath = GlobalEnvironmentHelper.isUsingCustomShell() 
    ? GlobalEnvironmentHelper.readShellPath() 
    : (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
  @State private var shellPathError: String?

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Shell")
            .font(.headline)
          
          Text("The shell used to start local servers, which will inherit the environment configured in that shell, unless an override is specified below.")
            .font(.caption)
            .foregroundColor(.secondary)
          
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
              Image(systemName: useCustomShell ? "circle" : "circle.inset.filled")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.15)) {
                    useCustomShell = false
                    saveShellSelection()
                  }
                }
              Text("Default login shell")
                .font(.system(size: 13))
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.15)) {
                    useCustomShell = false
                    saveShellSelection()
                  }
                }
              Spacer()
            }
            .frame(height: 20)
            
            HStack(spacing: 6) {
              Image(systemName: useCustomShell ? "circle.inset.filled" : "circle")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.15)) {
                    useCustomShell = true
                    saveShellSelection()
                  }
                }
              Text("Command (complete path):")
                .font(.system(size: 13))
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.15)) {
                    useCustomShell = true
                    saveShellSelection()
                  }
                }
              
              TextField("/path/to/shell", text: $shellPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .disabled(!useCustomShell)
                .onChange(of: shellPath) {
                  if useCustomShell {
                    saveShellSelection()
                  }
                }
                .frame(width: 280)
            }
            .frame(height: 20)
          }
          .padding(.leading, 20)
          
          if let error = shellPathError {
            Text(error)
              .font(.caption)
              .foregroundColor(.red)
          }
        }
        
        Divider()
        
        Text(
          "These global environment variables are set for all local servers. Any environment variables configured on the server itself will take precedence over the global environment. Inline variables (e.g. $PATH) that are specified in the environment value will be expanded using the login shell."
        )
        .font(.body)
        .foregroundColor(.secondary)

        VStack(spacing: 0) {
          if viewStore.environmentVariables.isEmpty {
            VStack(spacing: 8) {
              Text("No environment variables configured")
                .font(.caption)
                .foregroundColor(.secondary)
              Text("Click + to add an environment variable")
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: 150)
          } else {
            Table(
              viewStore.environmentVariables,
              selection: viewStore.binding(
                get: \.selectedId,
                send: GlobalEnvironmentFeature.Action.selectVariable
              )
            ) {
              TableColumn("Key") { item in
                FocusedTextField(
                  placeholder: "Variable name",
                  text: Binding(
                    get: { item.key },
                    set: { store.send(.keyChanged(item.id, $0)) }
                  ),
                  shouldFocus: item.shouldFocusKey,
                  onFocusHandled: {
                    store.send(.focusHandled(item.id, field: .key))
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

              TableColumn("Value") { item in
                FocusedTextField(
                  placeholder: "Variable value",
                  text: Binding(
                    get: { item.value },
                    set: { store.send(.valueChanged(item.id, $0)) }
                  ),
                  shouldFocus: item.shouldFocusValue,
                  onFocusHandled: {
                    store.send(.focusHandled(item.id, field: .value))
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
            }
            .alternatingRowBackgrounds(.disabled)
            .onDeleteCommand {
              store.send(.removeSelected)
            }
          }

          HStack(spacing: 0) {
            Button(action: {
              store.send(.addVariable)
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
      .onDisappear {
        store.send(.save)
      }
    }
  }
  
  private func saveShellSelection() {
    shellPathError = nil
    do {
      if useCustomShell {
        try GlobalEnvironmentHelper.writeShellPath(shellPath)
      } else {
        try GlobalEnvironmentHelper.writeShellPath(nil)
      }
    } catch {
      shellPathError = error.localizedDescription
      // Reset to previous state on error
      useCustomShell = GlobalEnvironmentHelper.isUsingCustomShell()
      shellPath = GlobalEnvironmentHelper.readShellPath()
    }
  }
}

