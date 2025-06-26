// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import SwiftUI

struct ChatView: View {
  let store: StoreOf<ChatFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      VStack(spacing: 0) {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(viewStore.messages) { message in
              MessageBubble(message: message)
            }
          }
          .padding()
        }

        Divider()

        MessageInputView(store: store)
      }
      .navigationTitle("Chat")
    }
  }
}

struct MessageBubble: View {
  let message: ChatMessage

  var body: some View {
    HStack {
      if message.isFromUser {
        Spacer()
      }

      VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
        Text(message.content)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 18)
              .fill(message.isFromUser ? Color.blue : Color(NSColor.controlBackgroundColor))
          )
          .foregroundColor(message.isFromUser ? .white : .primary)

        Text(message.timestamp, style: .time)
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      if !message.isFromUser {
        Spacer()
      }
    }
  }
}

struct MessageInputView: View {
  let store: StoreOf<ChatFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      HStack(spacing: 12) {
        TextField(
          "Type a message...",
          text: viewStore.binding(
            get: \.messageText,
            send: ChatFeature.Action.messageTextChanged
          )
        )
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          viewStore.send(.sendMessageButtonTapped)
        }

        Button("Send") {
          viewStore.send(.sendMessageButtonTapped)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewStore.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding()
    }
  }
}

#Preview {
  NavigationStack {
    ChatView(
      store: Store(initialState: ChatFeature.State()) {
        ChatFeature()
      }
    )
  }
}
