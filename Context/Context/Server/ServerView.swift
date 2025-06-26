// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI

struct ServerView: View {
  let store: StoreOf<ServerFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(spacing: 0) {
        if !viewStore.connectionErrors.isEmpty {
          ConnectionErrorBanner(
            errors: viewStore.connectionErrors,
            onDismiss: { viewStore.send(.clearErrors) }
          )
        }

        ServerTabContent(store: store, selectedTab: viewStore.selectedTab)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationTitle(viewStore.server.name)
      .navigationSubtitle(connectionStateText(for: viewStore.connectionState))
      .toolbar {
        ToolbarItem(placement: .principal) {
          ServerTabSwitcher(
            selectedTab: viewStore.selectedTab,
            onTabSelected: { tab in
              viewStore.send(.tabSelected(tab))
            }
          )
        }
      }
      .onAppear {
        viewStore.send(.onAppear)
      }
      .onDisappear {
        viewStore.send(.onDisappear)
      }
      .sheet(
        store: self.store.scope(
          state: \.$authenticationState,
          action: \.authenticationFeature
        )
      ) { store in
        AuthenticationView(store: store)
      }
    }
  }

  private func connectionStateText(for state: Client.ConnectionState) -> String {
    switch state {
    case .connecting: "Connecting"
    case .connected: "Connected"
    case .disconnected: "Disconnected"
    case .disconnecting: "Disconnecting"
    }
  }
}

// MARK: - Tab Content

struct ServerTabContent: View {
  let store: StoreOf<ServerFeature>
  let selectedTab: ServerTab

  var body: some View {
    Group {
      switch selectedTab {
      case .tools:
        ToolsView(store: store.scope(state: \.toolsFeature, action: \.toolsFeature))
      case .prompts:
        PromptsView(store: store.scope(state: \.promptsFeature, action: \.promptsFeature))
      case .resources:
        ResourcesView(store: store.scope(state: \.resourcesFeature, action: \.resourcesFeature))
      case .logs:
        LogsView(store: store.scope(state: \.logsFeature, action: \.logsFeature))
      }
    }
  }
}

// MARK: - Tab Switcher

struct ServerTabSwitcher: View {
  let selectedTab: ServerTab
  let onTabSelected: (ServerTab) -> Void

  var body: some View {
    HStack(spacing: 0) {
      ForEach(ServerTab.allCases, id: \.self) { tab in
        ServerTabButton(
          tab: tab,
          isSelected: selectedTab == tab,
          action: { onTabSelected(tab) }
        )

        if tab != ServerTab.allCases.last {
          ServerTabDivider(
            isHidden: shouldHideDivider(for: tab)
          )
        }
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color(NSColor.controlBackgroundColor))
        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func shouldHideDivider(for tab: ServerTab) -> Bool {
    guard let tabIndex = ServerTab.allCases.firstIndex(of: tab) else { return false }
    let nextIndex = tabIndex + 1
    guard nextIndex < ServerTab.allCases.count else { return false }

    return selectedTab == tab || selectedTab == ServerTab.allCases[nextIndex]
  }
}

// MARK: - Tab Button

struct ServerTabButton: View {
  let tab: ServerTab
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(tab.rawValue)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(isSelected ? .white : .primary)
        .frame(minWidth: 60, minHeight: 24)
        .padding(.horizontal, 12)
        .background(
          Rectangle()
            .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Tab Divider

struct ServerTabDivider: View {
  let isHidden: Bool

  var body: some View {
    Rectangle()
      .fill(Color(NSColor.separatorColor))
      .frame(width: 1)
      .opacity(isHidden ? 0 : 1)
  }
}

// MARK: - Connection Error Banner

struct ConnectionErrorBanner: View {
  let errors: [ConnectionError]
  let onDismiss: () -> Void

  @State private var showingErrorDetails = false

  private var latestError: ConnectionError? {
    errors.last
  }

  var body: some View {
    HStack(spacing: 12) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
          .font(.system(size: 16))

        if errors.count > 1 {
          Text("\(errors.count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.red)
            .clipShape(Capsule())
            .offset(x: 8, y: -6)
        }
      }

      if let latestError = latestError {
        Text(latestError.error)
          .font(.system(size: 13))
          .foregroundColor(.primary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button("Show Details") {
        showingErrorDetails = true
      }
      .buttonStyle(.link)
      .font(.system(size: 12))

      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.secondary)
          .font(.system(size: 16))
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color(NSColor.controlBackgroundColor))
    .overlay(
      Rectangle()
        .fill(Color(NSColor.separatorColor))
        .frame(height: 1),
      alignment: .bottom
    )
    .sheet(isPresented: $showingErrorDetails) {
      ErrorDetailsView(errors: errors)
    }
  }
}

// MARK: - Error Details View

struct ErrorDetailsView: View {
  let errors: [ConnectionError]
  @Environment(\.dismiss) private var dismiss

  private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .medium
    return formatter
  }()

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Label("Connection Error Details", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundColor(.orange)

        Spacer()

        Text("\(errors.count) error\(errors.count == 1 ? "" : "s")")
          .font(.subheadline)
          .foregroundColor(.secondary)

        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
      .padding()
      .background(Color(NSColor.windowBackgroundColor))

      Divider()

      // Error list
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(errors.reversed()) { error in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(dateFormatter.string(from: error.timestamp))
                  .font(.caption)
                  .foregroundColor(.secondary)

                Spacer()
              }

              Text(error.error)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
          }
        }
        .padding()
      }
      .frame(maxHeight: .infinity)
      .background(Color(NSColor.textBackgroundColor))
    }
    .frame(width: 600, height: 400)
  }
}

#Preview {
  NavigationStack {
    ServerView(
      store: Store(
        initialState: ServerFeature.State(
          server: MCPServer(
            id: UUID(),
            name: "example-server",
            transport: .stdio,
            command: "/usr/bin/example",
            args: [],
            environment: nil,
            headers: nil
          ))
      ) {
        ServerFeature()
      }
    )
  }
}
