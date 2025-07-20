// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ConnectionErrorDetailView: View {
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
