// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SVGView
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

        // MCP Metadata Display
        if let metadata = viewStore.mcpMetadata {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
              // Icon
              if let iconUrlString = metadata.icon,
                 let iconUrl = URL(string: iconUrlString) {
                // Check if the icon is an SVG
                if iconUrlString.lowercased().hasSuffix(".svg") {
                  SVGView(contentsOf: iconUrl)
                    .frame(width: 48, height: 48)
                } else {
                  AsyncImage(url: iconUrl) { image in
                    image
                      .resizable()
                      .aspectRatio(contentMode: .fit)
                  } placeholder: {
                    Image(systemName: "globe")
                      .foregroundColor(.secondary)
                  }
                  .frame(width: 48, height: 48)
                }
              } else {
                // Default icon if no URL provided
                Image(systemName: "globe")
                  .foregroundColor(.secondary)
                  .frame(width: 48, height: 48)
              }
              
              // Name and Description
              VStack(alignment: .leading, spacing: 4) {
                if let name = metadata.name {
                  Text(name)
                    .font(.title3)
                    .fontWeight(.medium)
                }
                
                if let description = metadata.description {
                  Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                }
                
                Text(metadata.endpoint)
                  .font(.caption.monospaced())
                  .foregroundColor(.blue)
                  .textSelection(.enabled)
              }
              
              Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
          }
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
