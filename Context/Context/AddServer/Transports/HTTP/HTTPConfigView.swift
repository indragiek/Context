// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct HTTPConfigView: View {
  let store: StoreOf<HTTPConfigFeature>
  @FocusState var isURLFocused: Bool
  let transport: TransportType

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in

      VStack(alignment: .leading, spacing: 16) {
        // URL
        VStack(alignment: .leading, spacing: 8) {
          Text("Server URL")
            .font(.headline)

          TextField(
            urlPlaceholder,
            text: viewStore.binding(get: \.url, send: HTTPConfigFeature.Action.urlChanged)
          )
          .textFieldStyle(.roundedBorder)
          .focused($isURLFocused)

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

          KeyValueListView(
            store: store.scope(state: \.headers, action: \.headers),
            keyHeader: "Header",
            valueHeader: "Value"
          )
        }
      }
      .onAppear {
        if viewStore.url.isEmpty {
          isURLFocused = true
        }
      }
    }
  }

  private var urlPlaceholder: String {
    transport == .sse ? "https://example.com/sse" : "https://example.com/mcp"
  }
}
