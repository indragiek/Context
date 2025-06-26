// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct AddServerView: View {
  @Bindable var store: StoreOf<AddServerFeature>

  var body: some View {
    VStack(spacing: 0) {
      // Content
      Group {
        switch store.screen {
        case .form:
          AddServerFormView(store: store)
        case let .error(message):
          AddServerErrorView(message: message)
        }
      }

      Divider()

      // Bottom Bar
      HStack {
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        switch store.screen {
        case .form:
          Button(buttonTitle(for: store.mode)) {
            store.send(.saveButtonTapped)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!store.isValid)

        case .error:
          Button("Try Again") {
            store.send(.cancelButtonTapped)
          }
          .keyboardShortcut(.defaultAction)
        }
      }
      .padding()
    }
    .frame(width: 600)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func buttonTitle(for mode: AddServerFeature.State.Mode) -> String {
    switch mode {
    case .add:
      return "Add Server"
    case .edit:
      return "Save Changes"
    }
  }
}

struct AddServerFormView: View {
  @Bindable var store: StoreOf<AddServerFeature>

  enum FocusField: Hashable {
    case serverName
    case serverURL
  }

  @FocusState private var focusedField: FocusField?

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      // Title
      Text(formTitle(for: store.mode))
        .font(.title2)
        .fontWeight(.semibold)
        .padding(.horizontal)
        .padding(.top)

      Divider()

      VStack(alignment: .leading, spacing: 20) {
        // Server Name
        VStack(alignment: .leading, spacing: 8) {
          Text("Server Name")
            .font(.headline)

          VStack(alignment: .leading, spacing: 4) {
            TextField(
              "Enter a unique name for this server",
              text: $store.serverName.sending(\.serverNameChanged)
            )
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .serverName)

            if let error = store.serverNameError {
              Text(error)
                .font(.caption)
                .foregroundColor(.red)
            }
          }
        }

        // Transport Type
        VStack(alignment: .leading, spacing: 8) {
          Text("Transport")
            .font(.headline)

          Picker("Transport", selection: $store.transport.sending(\.transportChanged)) {
            Text("Streamable HTTP").tag(TransportType.streamableHTTP)
            Text("stdio").tag(TransportType.stdio)
          }
          .pickerStyle(.segmented)
          .labelsHidden()

          Text(transportDescription)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        // Transport-specific fields
        Group {
          switch store.transport {
          case .stdio:
            StdioConfigurationView(store: store)
          case .sse, .streamableHTTP:
            URLConfigurationView(store: store, focusedField: $focusedField)
          }
        }
      }
      .padding(.horizontal)
      .padding(.bottom)
    }
    .onAppear {
      // Set initial focus based on transport type
      if store.transport == .streamableHTTP || store.transport == .sse {
        focusedField = .serverURL
      }
    }
  }

  private func formTitle(for mode: AddServerFeature.State.Mode) -> String {
    switch mode {
    case .add:
      return "Add MCP Server"
    case .edit:
      return "Edit MCP Server"
    }
  }

  private var transportDescription: String {
    switch store.transport {
    case .stdio:
      return "Standard I/O transport for local executable servers"
    case .sse:
      return "Server-Sent Events for real-time HTTP streaming"
    case .streamableHTTP:
      return "HTTP transport with streamable request/response support"
    }
  }
}

struct StdioConfigurationView: View {
  @Bindable var store: StoreOf<AddServerFeature>
  @State private var showingFilePicker = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Command
      VStack(alignment: .leading, spacing: 8) {
        Text("Command")
          .font(.headline)

        HStack(spacing: 8) {
          TextField("./server", text: $store.command.sending(\.commandChanged))
            .textFieldStyle(.roundedBorder)

          Button("Browse...") {
            showingFilePicker = true
          }
          .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.unixExecutable, .shellScript, .executable],
            allowsMultipleSelection: false
          ) { result in
            if case .success(let urls) = result, let url = urls.first {
              store.send(.commandChanged(url.path))
            }
          }
        }

        Text("Name or path to the MCP server executable")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      // Arguments/Environment
      VStack(alignment: .leading, spacing: 8) {
        // Tab selector - centered
        HStack {
          Spacer()
          ToggleButton(selection: $store.stdioTab.sending(\.stdioTabChanged))
            .fixedSize()
          Spacer()
        }

        VStack(spacing: 0) {
          if store.stdioTab == .arguments {
            if store.arguments.isEmpty {
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
                store.arguments,
                selection: Binding(
                  get: { store.selectedArgumentId },
                  set: { store.send(.selectArgument($0)) }
                )
              ) {
                TableColumn("Argument") { argument in
                  let binding = Binding(
                    get: { argument.value },
                    set: { store.send(.argumentChanged(argument.id, $0)) }
                  )
                  FocusedTextField(
                    placeholder: "",
                    text: binding,
                    shouldFocus: argument.shouldFocus,
                    onFocusHandled: {
                      store.send(.argumentFocusHandled(argument.id))
                    }
                  )
                }
              }
              .frame(height: 120)
              .alternatingRowBackgrounds(.disabled)
              .onDeleteCommand {
                store.send(.removeSelectedArgument)
              }
            }
          } else {
            // Environment Variables
            if store.environmentVariables.isEmpty {
              VStack(spacing: 8) {
                Text("No environment variables")
                  .font(.caption)
                  .foregroundColor(.secondary)
                Text("Click + to add environment variables")
                  .font(.caption)
                  .foregroundColor(Color.secondary.opacity(0.5))
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .frame(height: 120)
            } else {
              Table(
                store.environmentVariables,
                selection: Binding(
                  get: { store.selectedEnvironmentId },
                  set: { store.send(.selectEnvironmentVariable($0)) }
                )
              ) {
                TableColumn("Name") { env in
                  let binding = Binding(
                    get: { env.name },
                    set: { store.send(.environmentNameChanged(env.id, $0)) }
                  )
                  FocusedTextField(
                    placeholder: "",
                    text: binding,
                    shouldFocus: env.shouldFocusName,
                    onFocusHandled: {
                      store.send(.environmentFocusHandled(env.id))
                    }
                  )
                }
                .width(min: 150, ideal: 200)

                TableColumn("Value") { env in
                  let binding = Binding(
                    get: { env.value },
                    set: { store.send(.environmentValueChanged(env.id, $0)) }
                  )
                  TextField("", text: binding)
                    .textFieldStyle(.plain)
                }
              }
              .frame(height: 120)
              .alternatingRowBackgrounds(.disabled)
              .onDeleteCommand {
                store.send(.removeSelectedEnvironmentVariable)
              }
            }
          }

          HStack(spacing: 0) {
            if store.stdioTab == .arguments {
              Button(action: {
                store.send(.addArgument)
              }) {
                Image(systemName: "plus")
                  .frame(width: 20, height: 20)
              }
              .buttonStyle(.borderless)

              Button(action: { store.send(.removeSelectedArgument) }) {
                Image(systemName: "minus")
                  .frame(width: 20, height: 20)
              }
              .buttonStyle(.borderless)
              .disabled(store.selectedArgumentId == nil)
            } else {
              Button(action: {
                store.send(.addEnvironmentVariable)
              }) {
                Image(systemName: "plus")
                  .frame(width: 20, height: 20)
              }
              .buttonStyle(.borderless)

              Button(action: { store.send(.removeSelectedEnvironmentVariable) }) {
                Image(systemName: "minus")
                  .frame(width: 20, height: 20)
              }
              .buttonStyle(.borderless)
              .disabled(store.selectedEnvironmentId == nil)
            }

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
}

struct URLConfigurationView: View {
  @Bindable var store: StoreOf<AddServerFeature>
  @FocusState.Binding var focusedField: AddServerFormView.FocusField?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // URL
      VStack(alignment: .leading, spacing: 8) {
        Text("Server URL")
          .font(.headline)

        TextField(
          urlPlaceholder,
          text: $store.url.sending(\.urlChanged)
        )
        .textFieldStyle(.roundedBorder)
        .focused($focusedField, equals: .serverURL)

        Text("Modern HTTP streaming transport. The endpoint path is typically ")
          .font(.caption)
          .foregroundColor(.secondary)
          + Text("/mcp")
          .font(.caption.monospaced())
          .foregroundColor(.secondary)
          + Text(" or ")
          .font(.caption)
          .foregroundColor(.secondary)
          + Text("/sse")
          .font(.caption.monospaced())
          .foregroundColor(.secondary)
          + Text(" (legacy).")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      // Headers
      VStack(alignment: .leading, spacing: 8) {
        // Single toggle button for HTTP Headers
        HStack {
          Spacer()
          ToggleButton(
            items: [("HTTP Headers", "headers")],
            selection: .constant("headers")
          )
          .fixedSize()
          Spacer()
        }

        VStack(spacing: 0) {
          if store.headers.isEmpty {
            VStack(spacing: 8) {
              Text("No headers")
                .font(.caption)
                .foregroundColor(.secondary)
              Text("Click + to add HTTP headers")
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: 120)
          } else {
            Table(
              store.headers,
              selection: Binding(
                get: { store.selectedHeaderId },
                set: { store.send(.selectHeader($0)) }
              )
            ) {
              TableColumn("Header") { header in
                let binding = Binding(
                  get: { header.key },
                  set: { store.send(.headerKeyChanged(header.id, $0)) }
                )
                FocusedTextField(
                  placeholder: "",
                  text: binding,
                  shouldFocus: header.shouldFocusKey,
                  onFocusHandled: {
                    store.send(.headerFocusHandled(header.id))
                  }
                )
              }
              .width(min: 150, ideal: 200)

              TableColumn("Value") { header in
                let binding = Binding(
                  get: { header.value },
                  set: { store.send(.headerValueChanged(header.id, $0)) }
                )
                TextField("", text: binding)
                  .textFieldStyle(.plain)
              }
            }
            .frame(height: 120)
            .alternatingRowBackgrounds(.disabled)
            .onDeleteCommand {
              store.send(.removeSelectedHeader)
            }
          }

          HStack(spacing: 0) {
            Button(action: {
              store.send(.addHeader)
            }) {
              Image(systemName: "plus")
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)

            Button(action: { store.send(.removeSelectedHeader) }) {
              Image(systemName: "minus")
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(store.selectedHeaderId == nil)

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

  private var urlPlaceholder: String {
    store.transport == .sse ? "https://example.com/sse" : "https://example.com/mcp"
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
