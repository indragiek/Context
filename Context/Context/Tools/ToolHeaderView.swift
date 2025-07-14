// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import MarkdownUI
import SwiftUI

struct ToolHeaderView: View {
  let tool: Tool
  @Binding var showingFullDescription: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        toolInfo
        Spacer()
        annotationBadges
      }
    }
    .padding(20)
    .background(Color(NSColor.controlBackgroundColor))
  }

  @ViewBuilder
  private var toolInfo: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(tool.name)
        .font(.title2)
        .fontWeight(.semibold)

      if let description = tool.description {
        VStack(alignment: .leading, spacing: 4) {
          Text(LocalizedStringKey(description))
            .font(.callout)
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .lineLimit(3)

          Button(action: {
            showingFullDescription = true
          }) {
            Text("Show more")
              .font(.caption)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
        }
      } else {
        Button(action: {
          showingFullDescription = true
        }) {
          Text("Show more")
            .font(.caption)
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private var annotationBadges: some View {
    if let annotations = tool.annotations {
      HStack(spacing: 8) {
        if annotations.readOnlyHint == true {
          AnnotationBadge(
            label: "Read Only",
            color: .green,
            icon: "eye"
          )
        }

        if annotations.destructiveHint == true {
          AnnotationBadge(
            label: "Destructive",
            color: .red,
            icon: "exclamationmark.triangle"
          )
        }

        if annotations.idempotentHint == true {
          AnnotationBadge(
            label: "Idempotent",
            color: .blue,
            icon: "arrow.triangle.2.circlepath"
          )
        }

        if annotations.openWorldHint == true {
          AnnotationBadge(
            label: "Open World",
            color: .purple,
            icon: "globe"
          )
        }
      }
    }
  }
}

// MARK: - Full Description Sheet

extension ToolHeaderView {
  @ViewBuilder
  var fullDescriptionSheet: some View {
    VStack(spacing: 20) {
      HStack {
        Text(tool.name)
          .font(.title2)
          .fontWeight(.semibold)

        Spacer()

        Button("Done") {
          showingFullDescription = false
        }
        .keyboardShortcut(.defaultAction)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let description = tool.description {
            Markdown(description)
              .markdownTextStyle {
                ForegroundColor(.primary)
              }
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if let properties = tool.inputSchema.properties, !properties.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
              Text("Arguments")
                .font(.headline)

              let requiredSet = Set(tool.inputSchema.required ?? [])
              let sortedProperties = properties.sorted { $0.key < $1.key }

              ForEach(sortedProperties, id: \.key) { key, schema in
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(key)
                      .font(.subheadline)
                      .fontWeight(.medium)

                    if requiredSet.contains(key) {
                      Text("Required")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                          RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.2))
                        )
                        .foregroundColor(.red)
                    }

                    if let type = extractSchemaType(from: schema) {
                      Text(type)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                          RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.2))
                        )
                        .foregroundColor(.blue)
                    }
                  }

                  if let desc = extractDescription(from: schema) {
                    Markdown(desc)
                      .markdownTextStyle {
                        ForegroundColor(.secondary)
                      }
                      .font(.caption)
                      .textSelection(.enabled)
                  }
                }
                .padding(.vertical, 4)
              }
            }
          }

          if let annotations = tool.annotations {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
              Text("Annotations")
                .font(.headline)

              HStack(spacing: 12) {
                if annotations.readOnlyHint == true {
                  AnnotationBadge(
                    label: "Read Only",
                    color: .green,
                    icon: "eye"
                  )
                }

                if annotations.destructiveHint == true {
                  AnnotationBadge(
                    label: "Destructive",
                    color: .red,
                    icon: "exclamationmark.triangle"
                  )
                }

                if annotations.idempotentHint == true {
                  AnnotationBadge(
                    label: "Idempotent",
                    color: .blue,
                    icon: "arrow.triangle.2.circlepath"
                  )
                }

                if annotations.openWorldHint == true {
                  AnnotationBadge(
                    label: "Open World",
                    color: .purple,
                    icon: "globe"
                  )
                }
              }
            }
          }
        }
        .padding(.vertical)
      }
    }
    .padding(20)
    .frame(width: 600, height: 400)
  }

  private func extractSchemaType(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let typeStr) = obj["type"]
    {
      return typeStr
    }
    return nil
  }

  private func extractDescription(from schema: JSONValue) -> String? {
    if case .object(let obj) = schema,
      case .string(let desc) = obj["description"]
    {
      return desc
    }
    return nil
  }
}
