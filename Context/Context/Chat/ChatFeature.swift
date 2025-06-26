// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Foundation

@Reducer
struct ChatFeature {
  @ObservableState
  struct State: Equatable {
    var messages: IdentifiedArrayOf<ChatMessage> = []
    var messageText: String = ""
  }

  enum Action {
    case messageTextChanged(String)
    case sendMessageButtonTapped
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .messageTextChanged(text):
        state.messageText = text
        return .none

      case .sendMessageButtonTapped:
        guard !state.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return .none
        }

        let newMessage = ChatMessage(
          content: state.messageText,
          isFromUser: true,
          timestamp: Date()
        )
        state.messages.append(newMessage)
        state.messageText = ""

        // TODO: Implement actual message sending logic
        return .none
      }
    }
  }
}
