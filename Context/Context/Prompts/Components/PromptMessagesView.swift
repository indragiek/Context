// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct PromptMessagesView: View {
  let prompt: Prompt
  let promptState: PromptState
  @Binding var viewMode: PromptViewMode
  let isLoading: Bool
  let allRequiredArgumentsFilled: Bool
  let onFetchMessages: () -> Void
  let errorView: (any Error) -> AnyView
  let rawView: () -> AnyView
  
  var body: some View {
    VStack(spacing: 0) {
      // Fixed Messages Header
      MessagesHeader(
        viewMode: $viewMode,
        isLoading: isLoading,
        allRequiredArgumentsFilled: allRequiredArgumentsFilled,
        onFetchMessages: onFetchMessages
      )
      
      Divider()
      
      // Messages Content
      messagesContent
    }
    .frame(minHeight: 350)
  }
  
  @ViewBuilder
  private var messagesContent: some View {
    switch promptState.loadingState {
    case .idle:
      if viewMode == .raw {
        // Always show raw view when in raw mode
        rawView()
      } else {
        // Check if prompt has arguments that need to be filled
        let hasArguments = prompt.arguments != nil && !(prompt.arguments?.isEmpty ?? true)
        
        if hasArguments && !allRequiredArgumentsFilled {
          // Show prompt to fill arguments
          ContentUnavailableView(
            "No Messages",
            systemImage: "arrow.down.message",
            description: Text("Enter arguments and click the 􀈄 button to load messages")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !promptState.messages.isEmpty {
          // We have messages, show them
          messageDisplayView
        } else if promptState.hasLoadedOnce {
          // We've loaded before and there are no messages
          ContentUnavailableView(
            "No Messages Available",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("This prompt has no messages")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          // Initial state - haven't loaded yet
          if !hasArguments {
            // For prompts without arguments, show loading (auto-fetch should trigger)
            ProgressView()
              .controlSize(.regular)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            // For prompts with arguments, wait for user action
            ContentUnavailableView(
              "No Messages",
              systemImage: "arrow.down.message",
              description: Text("Click the 􀈄 button to load messages")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      
    case .loading:
      ProgressView()
        .controlSize(.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      
    case .loaded:
      if viewMode == .raw {
        // Always show raw view when in raw mode, regardless of messages
        rawView()
      } else if promptState.messages.isEmpty {
        ContentUnavailableView(
          "No Messages Available",
          systemImage: "bubble.left.and.bubble.right",
          description: Text("This prompt has no messages")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        messageDisplayView
      }
      
    case .failed(_, let underlyingError):
      if viewMode == .raw {
        // Show raw error data in raw mode
        rawView()
      } else if let error = underlyingError {
        errorView(error)
      } else {
        ContentUnavailableView(
          "Failed to Load Messages",
          systemImage: "exclamationmark.triangle",
          description: Text("Unable to fetch prompt messages")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
  
  @ViewBuilder
  private var messageDisplayView: some View {
    switch viewMode {
    case .preview:
      PromptMessagesList(
        messages: promptState.messages,
        argumentValues: promptState.argumentValues
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .raw:
      rawView()
    }
  }
}

private struct MessagesHeader: View {
  @Binding var viewMode: PromptViewMode
  let isLoading: Bool
  let allRequiredArgumentsFilled: Bool
  let onFetchMessages: () -> Void
  
  var body: some View {
    HStack {
      Text("Messages")
        .font(.headline)
      
      Spacer()
      
      ToggleButton(selection: $viewMode)
      
      Spacer()
      
      ZStack {
        ProgressView()
          .controlSize(.small)
          .opacity(isLoading ? 1 : 0)
      }
      .frame(width: 20)
      
      Button(action: onFetchMessages) {
        Image(systemName: "square.and.arrow.down")
          .font(.system(size: 14))
          .foregroundColor(.accentColor)
      }
      .buttonStyle(.plain)
      .disabled(isLoading || !allRequiredArgumentsFilled)
      .help(
        allRequiredArgumentsFilled
          ? "Get prompt messages" : "Fill in all required arguments to continue"
      )
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
    .background(Color(NSColor.controlBackgroundColor))
  }
}