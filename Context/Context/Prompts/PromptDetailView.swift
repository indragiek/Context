// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AVKit
import Combine
import ComposableArchitecture
import ContextCore
import Dependencies
import MarkdownUI
import SwiftUI

struct PromptDetailView: View {
  let prompt: Prompt
  let server: MCPServer
  let promptState: PromptState
  let onStateUpdate: (PromptState) -> Void
  
  // View-specific state only
  @FocusState private var focusedArgument: String?
  @State private var fetchTask: Task<Void, Never>?
  @State private var showingFullDescription = false
  
  // State that will be synced with PromptState
  @State private var localPromptState: PromptState
  
  init(
    prompt: Prompt, server: MCPServer, promptState: PromptState,
    onStateUpdate: @escaping (PromptState) -> Void
  ) {
    self.prompt = prompt
    self.server = server
    self.promptState = promptState
    self.onStateUpdate = onStateUpdate
    self._localPromptState = State(initialValue: promptState)
  }
  
  var body: some View {
    VSplitView {
      // Top pane - Header and arguments
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          PromptHeaderView(
            prompt: prompt,
            showingFullDescription: $showingFullDescription
          )
          
          Divider()
          
          PromptArgumentsView(
            arguments: prompt.arguments,
            argumentValues: $localPromptState.argumentValues,
            focusedArgument: $focusedArgument,
            allRequiredArgumentsFilled: allRequiredArgumentsFilled,
            isLoadingMessages: isLoadingMessages,
            onSubmit: fetchPromptMessages,
            onArgumentChange: updatePromptState,
            server: server,
            promptName: prompt.name
          )
          
          Spacer()
        }
        .padding(20)
      }
      .background(Color(NSColor.controlBackgroundColor))
      .frame(minHeight: 200, idealHeight: max(200, calculateIdealHeight()))
      
      // Bottom pane - Messages
      PromptMessagesView(
        prompt: prompt,
        promptState: localPromptState,
        viewMode: $localPromptState.viewMode,
        isLoading: isLoadingMessages,
        allRequiredArgumentsFilled: allRequiredArgumentsFilled,
        onFetchMessages: fetchPromptMessages,
        errorView: { error in
          AnyView(JSONRPCErrorView(error: error))
        },
        rawView: {
          AnyView(PromptRawDataView(promptState: localPromptState))
        }
      )
    }
    .sheet(isPresented: $showingFullDescription) {
      fullDescriptionSheet
    }
    .onAppear {
      initializeArguments()
      
      // Auto-fetch if prompt has no arguments
      if (prompt.arguments == nil || prompt.arguments?.isEmpty == true) && !localPromptState.hasLoadedOnce {
        fetchPromptMessages()
      }
    }
    .onDisappear {
      fetchTask?.cancel()
      fetchTask = nil
    }
  }
  
  // MARK: - Private Helpers
  
  private func initializeArguments() {
    if let arguments = prompt.arguments {
      for argument in arguments {
        if localPromptState.argumentValues[argument.name] == nil {
          localPromptState.argumentValues[argument.name] = ""
        }
      }
    }
  }
  
  private func updatePromptState() {
    onStateUpdate(localPromptState)
  }
  
  private var allRequiredArgumentsFilled: Bool {
    guard let arguments = prompt.arguments else { return true }
    
    return arguments.allSatisfy { argument in
      if argument.required == true {
        let value = localPromptState.argumentValues[argument.name] ?? ""
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      return true
    }
  }
  
  private var isLoadingMessages: Bool {
    localPromptState.loadingState == .loading
  }
  
  private func calculateIdealHeight() -> CGFloat {
    let baseHeight: CGFloat = 160
    let argumentHeight: CGFloat = 40
    let argumentsCount = min(prompt.arguments?.count ?? 0, 3)
    return baseHeight + (CGFloat(argumentsCount) * argumentHeight)
  }
  
  private func fetchPromptMessages() {
    @Dependency(\.mcpClientManager) var mcpClientManager
    
    fetchTask?.cancel()
    
    localPromptState.loadingState = .loading
    updatePromptState()
    
    fetchTask = Task { @MainActor in
      do {
        let client = try await mcpClientManager.client(for: server)
        
        if Task.isCancelled { return }
        
        let (description, fetchedMessages) = try await client.getPrompt(
          name: prompt.name, arguments: localPromptState.argumentValues)
        
        if Task.isCancelled { return }
        
        await MainActor.run {
          localPromptState.rawResponse = GetPromptResponse.Result(
            description: description, messages: fetchedMessages)
          
          do {
            // Create the response structure to encode
            let responseToEncode = GetPromptResponse.Result(
              description: description,
              messages: fetchedMessages
            )
            
            // TODO: Fix this inefficient encoding/decoding. We do this because we don't have access
            // to the raw JSON responses from the client.
            let jsonData = try JSONUtility.prettyData(from: responseToEncode)
            localPromptState.responseJSON = try JSONDecoder().decode(JSONValue.self, from: jsonData)
            localPromptState.responseError = nil
          } catch {
            localPromptState.responseJSON = nil
            localPromptState.responseError = error
          }
          
          let templateProcessor = TemplateProcessor(argumentValues: localPromptState.argumentValues)
          localPromptState.messages = fetchedMessages.map { message in
            PromptMessage(
              role: message.role,
              content: templateProcessor.process(message.content)
            )
          }
          
          localPromptState.loadingState = .loaded
          localPromptState.hasLoadedOnce = true
          
          updatePromptState()
        }
      } catch {
        if Task.isCancelled { return }
        
        await MainActor.run {
          localPromptState.messages = []
          localPromptState.rawResponse = nil
          localPromptState.responseJSON = nil
          localPromptState.responseError = error
          localPromptState.loadingState = .failed
          localPromptState.hasLoadedOnce = true
          
          updatePromptState()
        }
      }
    }
  }
}

// MARK: - PromptMessagesList

struct PromptMessagesList: View {
  let messages: [PromptMessage]
  let argumentValues: [String: String]
  
  var body: some View {
    MessageThreadView(messages: messages)
  }
}

// MARK: - Full Description Sheet

extension PromptDetailView {
  @ViewBuilder
  private var fullDescriptionSheet: some View {
    VStack(spacing: 20) {
      HStack {
        Text(prompt.name)
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
          if let description = prompt.description {
            Markdown(description)
              .markdownTextStyle {
                ForegroundColor(.primary)
              }
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          
          if let arguments = prompt.arguments, !arguments.isEmpty {
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
              Text("Arguments")
                .font(.headline)
              
              ForEach(arguments, id: \.name) { argument in
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(argument.name)
                      .font(.subheadline)
                      .fontWeight(.medium)
                    
                    if argument.required ?? false {
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
                  }
                  
                  if let desc = argument.description {
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
        }
        .padding(.vertical)
      }
    }
    .padding(20)
    .frame(width: 600, height: 400)
  }
}