// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct AddServerView: View {
  let store: StoreOf<AddServerFeature>

  var body: some View {
    WithViewStore(self.store, observe: \.screen) { viewStore in
      VStack(spacing: 0) {
        // Content
        Group {
          switch viewStore.state {
          case .form:
            AddServerFormView(store: store)
          case let .error(message):
            AddServerErrorView(message: message)
          }
        }

        Divider()

        // Bottom Bar
        AddServerBottomBar(store: store)
          .padding()
      }
      .frame(width: 600)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct AddServerFormView: View {
  let store: StoreOf<AddServerFeature>

  var body: some View {
    WithViewStore(self.store, observe: \.mode) { viewStore in
      VStack(alignment: .leading, spacing: 20) {
        // Title
        AddServerHeader(mode: viewStore.state)
          .padding(.horizontal)
          .padding(.top)

        Divider()

        VStack(alignment: .leading, spacing: 20) {
          // Server Name
          ServerNameSection(store: store)

          // Transport Type
          TransportSelector(store: store)

          // Transport-specific fields
          TransportConfigurationSection(store: store)
        }
        .padding(.horizontal)
        .padding(.bottom)
      }
    }
  }
}

// MARK: - Components

struct AddServerHeader: View {
  let mode: AddServerMode

  var body: some View {
    Text(title)
      .font(.title2)
      .fontWeight(.semibold)
  }

  private var title: String {
    switch mode {
    case .add:
      return "Add MCP Server"
    case .edit:
      return "Edit MCP Server"
    }
  }
}

struct ServerNameSection: View {
  let store: StoreOf<AddServerFeature>
  @FocusState private var isFocused: Bool

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(alignment: .leading, spacing: 8) {
        Text("Server Name")
          .font(.headline)

        VStack(alignment: .leading, spacing: 4) {
          TextField(
            "Enter a unique name for this server",
            text: viewStore.binding(
              get: \.serverName, send: AddServerFeature.Action.serverNameChanged)
          )
          .textFieldStyle(.roundedBorder)
          .focused($isFocused)
          .accessibilityLabel("Server name")
          .accessibilityHint("Enter a unique name to identify this server")

          if let error = viewStore.serverNameError {
            Text(error)
              .font(.caption)
              .foregroundColor(.red)
          }
        }
      }
    }
  }
}

struct TransportSelector: View {
  let store: StoreOf<AddServerFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(alignment: .leading, spacing: 8) {
        Text("Transport")
          .font(.headline)

        Picker(
          "Transport",
          selection: viewStore.binding(
            get: \.transport, send: AddServerFeature.Action.transportChanged)
        ) {
          Text("Streamable HTTP").tag(TransportType.streamableHTTP)
          Text("stdio").tag(TransportType.stdio)
          Text("DXT").tag(TransportType.dxt)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Transport type")
        .accessibilityHint("Select the communication protocol for this server")

        Text(transportDescription(for: viewStore.transport))
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  private func transportDescription(for transport: TransportType) -> String {
    switch transport {
    case .stdio:
      return "Standard I/O transport for local executable servers"
    case .sse:
      return "Server-Sent Events for real-time HTTP streaming"
    case .streamableHTTP:
      return "HTTP transport with streamable request/response support"
    case .dxt:
      return "Desktop Extension format for packaged MCP servers"
    }
  }
}

struct TransportConfigurationSection: View {
  let store: StoreOf<AddServerFeature>

  var body: some View {
    Group {
      switch store.transport {
      case .stdio:
        StdioConfigView(
          store: store.scope(state: \.stdioConfig, action: \.stdioConfig)
        )
      case .sse, .streamableHTTP:
        HTTPConfigView(
          store: store.scope(state: \.httpConfig, action: \.httpConfig),
          transport: store.transport
        )
      case .dxt:
        DXTConfigView(
          store: store.scope(state: \.dxtConfig, action: \.dxtConfig)
        )
      }
    }
  }
}

struct AddServerBottomBar: View {
  let store: StoreOf<AddServerFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      HStack {
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Cancel")
        .accessibilityHint("Closes the dialog without saving changes")

        Spacer()

        switch viewStore.screen {
        case .form:
          Button(buttonTitle(for: viewStore.mode)) {
            store.send(.saveButtonTapped)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!viewStore.isValid)
          .accessibilityLabel(buttonTitle(for: viewStore.mode))
          .accessibilityHint(
            viewStore.isValid
              ? "Saves the server configuration" : "Complete all required fields to enable")

        case .error:
          Button("Try Again") {
            store.send(.cancelButtonTapped)
          }
          .keyboardShortcut(.defaultAction)
        }
      }
    }
  }

  private func buttonTitle(for mode: AddServerMode) -> String {
    switch mode {
    case .add:
      return "Add Server"
    case .edit:
      return "Save Changes"
    }
  }
}

struct AddServerErrorView: View {
  let message: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 64))
        .foregroundColor(.red)

      Text("Error Adding Server")
        .font(.title2)
        .fontWeight(.semibold)

      Text(message)
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

#Preview {
  AddServerView(
    store: Store(initialState: AddServerFeature.State()) {
      AddServerFeature()
    }
  )
}
