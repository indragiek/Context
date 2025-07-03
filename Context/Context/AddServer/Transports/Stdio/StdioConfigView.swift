// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct StdioConfigView: View {
  let store: StoreOf<StdioConfigFeature>
  @State private var showingFilePicker = false

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in

      VStack(alignment: .leading, spacing: 16) {
        // Command
        VStack(alignment: .leading, spacing: 8) {
          Text("Command")
            .font(.headline)

          HStack(spacing: 8) {
            TextField(
              "./server",
              text: viewStore.binding(
                get: \.command, send: StdioConfigFeature.Action.commandChanged)
            )
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
            ToggleButton(
              selection: viewStore.binding(
                get: \.stdioTab, send: StdioConfigFeature.Action.stdioTabChanged)
            )
            .fixedSize()
            Spacer()
          }

          if viewStore.stdioTab == .arguments {
            ArgumentListView(
              store: store.scope(state: \.arguments, action: \.arguments)
            )
          } else {
            KeyValueListView(
              store: store.scope(state: \.environmentVariables, action: \.environmentVariables),
              keyHeader: "Name",
              valueHeader: "Value"
            )
          }
        }
      }
    }
  }
}
