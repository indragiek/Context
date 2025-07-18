// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AVKit
import ComposableArchitecture
import ContextCore
import MarkdownUI
import SwiftUI

/// A generic message that can be displayed in the message thread
protocol ThreadMessage {
  var role: Role { get }
  var content: Content { get }
}

/// Make PromptMessage conform to ThreadMessage
extension PromptMessage: ThreadMessage {}

/// A message for tool responses
struct ToolResponseMessage: ThreadMessage {
  let content: Content

  var role: Role {
    .assistant
  }
}

/// A reusable message thread view that displays messages with different content types
struct MessageThreadView<Message: ThreadMessage>: View {
  let messages: [Message]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
          ThreadMessageBubble(message: message)
        }
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// A message bubble that displays different types of content
struct ThreadMessageBubble<Message: ThreadMessage>: View {
  let message: Message
  @State private var showingResourcePopover = false

  private var annotationTooltip: String? {
    switch message.content {
    case .text(_, let annotations),
      .image(_, _, let annotations),
      .audio(_, _, let annotations),
      .resource(_, let annotations):
      guard let annotations = annotations else { return nil }

      var tooltip = ""

      if let audience = annotations.audience {
        tooltip += "Audience: \(audience.map { $0.rawValue }.joined(separator: ", "))"
      }

      if let priority = annotations.priority {
        if !tooltip.isEmpty { tooltip += "\n" }
        tooltip += "Priority: \(String(format: "%.1f", priority))"
      }

      return tooltip.isEmpty ? nil : tooltip
    }
  }

  private var embeddedResourceForPopover: EmbeddedResource? {
    switch message.content {
    case .image(let data, let mimeType, _):
      return .blob(
        BlobResourceContents(
          uri: "image://message",
          mimeType: mimeType,
          blob: data
        ))
    case .audio(let data, let mimeType, _):
      return .blob(
        BlobResourceContents(
          uri: "audio://message",
          mimeType: mimeType,
          blob: data
        ))
    case .resource(let embeddedResource, _):
      return embeddedResource
    default:
      return nil
    }
  }

  var body: some View {
    HStack {
      if message.role == .user {
        Spacer()
      }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
        contentView
      }

      if message.role == .assistant {
        Spacer()
      }
    }
  }

  @ViewBuilder
  private var contentView: some View {
    switch message.content {
    case .text(let text, _):
      textBubble(text: text)

    case .image(let data, _, _):
      imageBubble(data: data)

    case .audio(let data, let mimeType, _):
      audioBubble(data: data, mimeType: mimeType)

    case .resource(let embeddedResource, _):
      resourceBubble(embeddedResource: embeddedResource)
    }
  }

  private func textBubble(text: String) -> some View {
    Group {
      if JSONUtility.isLikelyJSON(text) {
        JSONContentView(
          contentLines: text.components(separatedBy: .newlines),
          searchText: "",
          isSearchActive: false
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 18)
            .fill(message.role == .user ? Color.blue : Color(NSColor.controlBackgroundColor))
        )
        .help(annotationTooltip ?? "")
        .contextMenu {
          Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
          }) {
            Text("Copy Message")
          }
        }
      } else {
        Markdown(text)
          .markdownTextStyle {
            ForegroundColor(message.role == .user ? .white : .primary)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 18)
              .fill(message.role == .user ? Color.blue : Color(NSColor.controlBackgroundColor))
          )
          .textSelection(.enabled)
          .help(annotationTooltip ?? "")
          .contextMenu {
            Button(action: {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(text, forType: .string)
            }) {
              Text("Copy Message")
            }
          }
      }
    }
  }

  private func imageBubble(data: Data) -> some View {
    HStack {
      if let nsImage = NSImage(data: data) {
        Image(nsImage: nsImage)
          .scaledToFit()

      } else {
        Image(systemName: "photo")
          .font(.largeTitle)
          .frame(width: 100, height: 100)
      }

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.leading, 4)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 18)
        .fill(
          message.role == .user ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
    )
    .onTapGesture {
      showingResourcePopover = true
    }
    .popover(isPresented: $showingResourcePopover) {
      if let resource = embeddedResourceForPopover {
        EmbeddedResourceContentView(resource: resource)
          .frame(minWidth: 600, idealWidth: 800, minHeight: 400, idealHeight: 600)
      }
    }
    .help(annotationTooltip ?? "Click to view full image")
  }

  private func audioBubble(data: Data, mimeType: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "waveform")
        .font(.title2)
        .foregroundColor(message.role == .user ? .blue : .primary)

      VStack(alignment: .leading, spacing: 2) {
        Text("Audio Message")
          .font(.callout)
          .fontWeight(.medium)

        Text(mimeType)
          .font(.caption2)
          .foregroundColor(.secondary)

        Text("\(data.count) bytes")
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 18)
        .fill(
          message.role == .user ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
    )
    .onTapGesture {
      showingResourcePopover = true
    }
    .popover(isPresented: $showingResourcePopover) {
      if let resource = embeddedResourceForPopover {
        EmbeddedResourceContentView(resource: resource)
          .frame(minWidth: 600, idealWidth: 800, minHeight: 400, idealHeight: 600)
      }
    }
    .help(annotationTooltip ?? "Click to preview audio")
  }

  private func resourceBubble(embeddedResource: EmbeddedResource) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "doc.richtext")
        .font(.body)

      VStack(alignment: .leading, spacing: 2) {
        Text(resourceURI(from: embeddedResource))
          .font(.caption)
          .fontWeight(.medium)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 200, alignment: .leading)

        if let mimeType = resourceMimeType(from: embeddedResource) {
          Text(mimeType)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 18)
        .fill(
          message.role == .user ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
    )
    .onTapGesture {
      showingResourcePopover = true
    }
    .popover(isPresented: $showingResourcePopover) {
      if let resource = embeddedResourceForPopover {
        EmbeddedResourceContentView(resource: resource)
          .frame(minWidth: 600, idealWidth: 800, minHeight: 400, idealHeight: 600)
      }
    }
    .help(annotationTooltip ?? "Click to view resource")
  }

  private func resourceURI(from resource: EmbeddedResource) -> String {
    switch resource {
    case .text(let textResource):
      return textResource.uri
    case .blob(let blobResource):
      return blobResource.uri
    }
  }

  private func resourceMimeType(from resource: EmbeddedResource) -> String? {
    switch resource {
    case .text(let textResource):
      return textResource.mimeType
    case .blob(let blobResource):
      return blobResource.mimeType
    }
  }
}
