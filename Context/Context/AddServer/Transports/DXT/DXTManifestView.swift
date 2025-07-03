// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct DXTManifestView: View {
  let jsonValue: JSONValue?
  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""

  init(manifestData: Data) {
    self.jsonValue = try? JSONDecoder().decode(JSONValue.self, from: manifestData)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("DXT Manifest")
          .font(.title2)
          .fontWeight(.semibold)

        Spacer()

        HStack(spacing: 12) {
          SearchField(text: $searchText)
            .frame(width: 200)

          Button("Done") {
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
        }
      }
      .padding()

      Divider()

      // Manifest content
      if let jsonValue = jsonValue {
        JSONRawView(
          jsonValue: jsonValue, searchText: searchText, isSearchActive: !searchText.isEmpty)
      } else {
        VStack {
          Spacer()
          Text("Unable to display manifest")
            .foregroundColor(.secondary)
          Spacer()
        }
      }
    }
    .frame(width: 800, height: 600)
  }
}
