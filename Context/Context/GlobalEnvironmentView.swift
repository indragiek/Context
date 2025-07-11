// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct GlobalEnvironmentView: View {
  let store: StoreOf<GlobalEnvironmentFeature>
  
  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(alignment: .leading, spacing: 16) {
        shellConfigurationSection(viewStore)
        
        Divider()
        
        environmentVariablesSection(viewStore)
        
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
        // Save shell configuration when view disappears
        if viewStore.shellSelection == .custom && !viewStore.shellPath.isEmpty && viewStore.shellPathError == nil {
          store.send(.saveShellConfiguration)
        }
      }
    }
  }
  
  @ViewBuilder
  private func shellConfigurationSection(_ viewStore: ViewStoreOf<GlobalEnvironmentFeature>) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("", selection: viewStore.binding(
        get: \.shellSelection,
        send: GlobalEnvironmentFeature.Action.shellSelectionChanged
      )) {
        Text("Default login shell").tag(GlobalEnvironmentFeature.State.ShellSelection.loginShell)
        Text("Command (complete path)").tag(GlobalEnvironmentFeature.State.ShellSelection.custom)
      }
      .pickerStyle(.radioGroup)
      .labelsHidden()
      
      HStack(spacing: 8) {
        TextField("/path/to/shell", text: viewStore.binding(
          get: \.shellPath,
          send: GlobalEnvironmentFeature.Action.shellPathChanged
        ))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
        .disabled(viewStore.shellSelection == .loginShell)
        .onSubmit {
          if viewStore.shellSelection == .custom {
            store.send(.saveShellConfiguration)
          }
        }
        .overlay(alignment: .topTrailing) {
          if let error = viewStore.shellPathError {
            Text(error)
              .font(.caption)
              .foregroundColor(.red)
              .offset(y: -20)
          }
        }
        
        Menu("Import from...") {
          ForEach(TerminalApp.allCases) { terminal in
            if terminal.isInstalled {
              Button(action: {
                store.send(.importShellFrom(terminal))
              }) {
                Label(terminal.name, image: terminal.icon)
              }
            }
          }
        }
        .controlSize(.regular)
        .fixedSize()
        .disabled(viewStore.shellSelection == .loginShell)
        .overlay(alignment: .topLeading) {
          if viewStore.showImportSuccess {
            successIndicator
              .offset(y: -24)
          }
        }
      }
      
      Text("The shell used to start local servers, which will inherit the environment configured in that shell, unless an override is specified below.")
        .font(.footnote)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
  
  @ViewBuilder
  private func environmentVariablesSection(_ viewStore: ViewStoreOf<GlobalEnvironmentFeature>) -> some View {
    VStack(alignment: .leading, spacing: 12) {
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
      
      Text(
        "These global environment variables are set for all local servers. Any environment variables configured on the server itself will take precedence over the global environment. Inline variables (e.g. $PATH) that are specified in the environment value will be expanded using the configured shell."
      )
      .font(.footnote)
      .foregroundColor(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
  
  private var successIndicator: some View {
    HStack(spacing: 4) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
        .font(.system(size: 13))
      Text("Imported shell")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
    }
    .transition(.opacity.combined(with: .scale(scale: 0.9)))
  }
}

extension Label where Title == Text, Icon == Image {
  init(_ title: String, image nsImage: NSImage) {
    self.init {
      Text(title)
    } icon: {
      Image(nsImage: nsImage)
    }
  }
}