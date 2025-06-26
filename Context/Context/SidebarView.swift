// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI

struct SidebarView: View {
  @Bindable var store: StoreOf<AppFeature>
  @State private var selection: SidebarItem?

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      SidebarList(
        selection: $selection,
        servers: Array(viewStore.servers),
        selectedSidebarItem: viewStore.sidebarFeature.selectedSidebarItem,
        onAddServer: { viewStore.send(.sidebarFeature(.addServerButtonTapped)) },
        onReloadServer: { serverId in
          viewStore.send(.serverLifecycleFeature(.reloadServerConnection(serverId)))
        },
        onConnectServer: { serverId in
          viewStore.send(.serverLifecycleFeature(.reloadServerConnection(serverId)))
        },
        onDisconnectServer: { serverId in
          viewStore.send(.serverLifecycleFeature(.disconnectServer(serverId)))
        },
        onRenameServer: { serverId, newName in
          viewStore.send(.sidebarFeature(.renameServer(id: serverId, newName: newName)))
        },
        onEditServer: { server in viewStore.send(.sidebarFeature(.editServerTapped(server))) },
        onDeleteServer: { server in viewStore.send(.sidebarFeature(.deleteServerTapped(server))) }
      )
      .navigationTitle("Context")
      .onAppear {
        selection = viewStore.sidebarFeature.selectedSidebarItem
      }
      .onChange(of: selection) { _, newValue in
        handleSelectionChange(newValue, viewStore: viewStore)
      }
      .onChange(of: viewStore.sidebarFeature.selectedSidebarItem) { _, newValue in
        selection = newValue
      }
      .sheet(
        item: $store.scope(
          state: \.sidebarFeature.importWizard, action: \.sidebarFeature.importWizard)
      ) { store in
        ImportWizardView(store: store)
      }
      .sheet(
        item: $store.scope(state: \.sidebarFeature.addServer, action: \.sidebarFeature.addServer)
      ) { store in
        AddServerView(store: store)
      }
      .sheet(
        item: $store.scope(state: \.sidebarFeature.editServer, action: \.sidebarFeature.editServer)
      ) { store in
        AddServerView(store: store)
      }
      .alert(
        $store.scope(
          state: \.sidebarFeature.deleteConfirmation, action: \.sidebarFeature.deleteConfirmation)
      )
      .alert(
        $store.scope(state: \.sidebarFeature.renameError, action: \.sidebarFeature.renameError)
      )
      .onReceive(NotificationCenter.default.publisher(for: .importMCPServers)) { _ in
        viewStore.send(.sidebarFeature(.importMenuItemTapped))
      }
      .onReceive(NotificationCenter.default.publisher(for: .addMCPServer)) { _ in
        viewStore.send(.sidebarFeature(.addServerButtonTapped))
      }
    }
  }

  private func handleSelectionChange(
    _ newValue: SidebarItem?, viewStore: ViewStore<AppFeature.State, AppFeature.Action>
  ) {
    guard let newValue else { return }
    Task {
      switch newValue {
      case .chat:
        viewStore.send(.sidebarFeature(.sidebarItemSelected(.chat)))
      case .server(let id):
        viewStore.send(.sidebarFeature(.serverSelected(id)))
      }
    }
  }
}

// MARK: - Sidebar List

struct SidebarList: View {
  @Binding var selection: SidebarItem?
  let servers: [ServerFeature.State]
  let selectedSidebarItem: SidebarItem?
  let onAddServer: () -> Void
  let onReloadServer: (UUID) -> Void
  let onConnectServer: (UUID) -> Void
  let onDisconnectServer: (UUID) -> Void
  let onRenameServer: (UUID, String) -> Void
  let onEditServer: (MCPServer) -> Void
  let onDeleteServer: (MCPServer) -> Void

  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(spacing: 0) {
      List(selection: $selection) {
        ServersSection(
          servers: servers,
          selectedSidebarItem: selectedSidebarItem,
          onAddServer: onAddServer,
          onReloadServer: onReloadServer,
          onConnectServer: onConnectServer,
          onDisconnectServer: onDisconnectServer,
          onRenameServer: onRenameServer,
          onEditServer: onEditServer,
          onDeleteServer: onDeleteServer
        )
      }
      .listStyle(.sidebar)

      Divider()

      // Feedback button at the bottom
      #if !SENTRY_DISABLED
        Button(action: {
          openWindow(id: "feedback")
        }) {
          HStack {
            Image(systemName: "exclamationmark.bubble")
              .font(.callout)
            Text("Give Feedback")
              .font(.callout)
            Spacer()
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      #endif
    }
    .frame(minWidth: 200)
  }
}

// MARK: - Servers Section

struct ServersSection: View {
  let servers: [ServerFeature.State]
  let selectedSidebarItem: SidebarItem?
  let onAddServer: () -> Void
  let onReloadServer: (UUID) -> Void
  let onConnectServer: (UUID) -> Void
  let onDisconnectServer: (UUID) -> Void
  let onRenameServer: (UUID, String) -> Void
  let onEditServer: (MCPServer) -> Void
  let onDeleteServer: (MCPServer) -> Void

  var body: some View {
    Section {
      ForEach(servers, id: \.id) { serverState in
        ServerNavigationLink(
          server: serverState.server,
          connectionState: serverState.connectionState,
          isSelected: selectedSidebarItem == .server(id: serverState.id),
          onReload: { onReloadServer(serverState.id) },
          onConnect: { onConnectServer(serverState.id) },
          onDisconnect: { onDisconnectServer(serverState.id) },
          onRename: { newName in onRenameServer(serverState.id, newName) },
          onEdit: { onEditServer(serverState.server) },
          onDelete: { onDeleteServer(serverState.server) }
        )
      }
    } header: {
      ServersSectionHeader(onAddServer: onAddServer)
    }
  }
}

// MARK: - Server Navigation Link

struct ServerNavigationLink: View {
  let server: MCPServer
  let connectionState: Client.ConnectionState
  let isSelected: Bool
  let onReload: () -> Void
  let onConnect: () -> Void
  let onDisconnect: () -> Void
  let onRename: (String) -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  @State private var isRenaming = false
  @State private var editedName = ""
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    NavigationLink(value: SidebarItem.server(id: server.id)) {
      HStack {
        if isRenaming {
          HStack {
            Image(systemName: "server.rack")
              .font(.callout)
            TextField(
              "Server Name", text: $editedName,
              onCommit: {
                if !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  onRename(editedName.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                isRenaming = false
                isTextFieldFocused = false
              }
            )
            .textFieldStyle(.plain)
            .focused($isTextFieldFocused)
            .onExitCommand {
              // Cancel editing on Escape key
              isRenaming = false
              isTextFieldFocused = false
              editedName = server.name
            }
            .onAppear {
              editedName = server.name
              // Delay focus to ensure TextField is ready
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
              }
            }
          }
        } else {
          Label(server.name, systemImage: "server.rack")
        }
        Spacer()
        ConnectionStateIcon(
          state: connectionState,
          isSelected: isSelected,
          onReload: onReload
        )
      }
    }
    .contextMenu {
      // Connect/Disconnect
      if connectionState == .connected {
        Button("Disconnect") {
          onDisconnect()
        }
      } else if connectionState == .disconnected {
        Button("Connect") {
          onConnect()
        }
      }

      Divider()

      Button("Rename") {
        isRenaming = true
      }

      Button("Edit...") {
        onEdit()
      }

      Divider()

      Button("Delete...") {
        onDelete()
      }
    }
  }
}

// MARK: - Servers Section Header

struct ServersSectionHeader: View {
  let onAddServer: () -> Void

  var body: some View {
    HStack {
      Text("Servers")
      Spacer()
      Button(action: onAddServer) {
        Image(systemName: "plus")
          .font(.caption)
      }
      .buttonStyle(.borderless)
    }
    .padding(.trailing, 8)
  }
}

#Preview {
  NavigationSplitView {
    SidebarView(
      store: Store(initialState: AppFeature.State()) {
        AppFeature()
      }
    )
  } detail: {
    Text("Detail View")
  }
}
