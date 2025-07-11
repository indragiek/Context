// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import ContextCore
import SwiftUI

struct ToolResponseView: View {
  let hasLoadedOnce: Bool
  let toolResponse: CallToolResponse.Result?
  let responseJSON: JSONValue?
  let responseError: (any Error)?
  @Binding var viewMode: ToolViewMode
  let canCallTool: Bool
  let isLoading: Bool
  let onRunTool: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      responseHeader
      Divider()
      responseContent
    }
  }

  @ViewBuilder
  private var responseHeader: some View {
    HStack(spacing: 12) {
      Text("Response")
        .font(.headline)

      Spacer()

      // Copy button when in Raw mode
      if viewMode == .raw && shouldShowCopyButton {
        CopyButton {
          copyRawDataToClipboard()
        }
        .help("Copy raw JSON to clipboard")
      }

      runToolButton
    }
    .padding(.horizontal, 20)
    .frame(height: 50)
    .background(Color(NSColor.controlBackgroundColor))
    .overlay(
      // Centered toggle buttons
      ToggleButton(selection: $viewMode)
    )
  }

  @ViewBuilder
  private var runToolButton: some View {
    Button(action: onRunTool) {
      ZStack {
        Image(systemName: "play.fill")
          .font(.system(size: 16))
          .foregroundColor(.accentColor)
          .opacity(isLoading ? 0 : 1)

        if isLoading {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.8)
        }
      }
    }
    .buttonStyle(.plain)
    .disabled(!canCallTool || isLoading)
    .help("Run Tool (⌘↩)")
  }

  @ViewBuilder
  private var responseContent: some View {
    if hasLoadedOnce {
      if let response = toolResponse {
        Group {
          switch viewMode {
          case .preview:
            let messages = response.content.map { content in
              ToolResponseMessage(content: content)
            }
            MessageThreadView(messages: messages)
          case .raw:
            RawDataView(
              responseJSON: responseJSON,
              responseError: responseError
            )
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if responseError != nil {
        // Error state
        Group {
          switch viewMode {
          case .preview:
            if let error = responseError {
              JSONRPCErrorView(error: error)
            }
          case .raw:
            RawDataView(
              responseJSON: responseJSON,
              responseError: responseError
            )
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "No Response",
          systemImage: "function",
          description: Text("Tool call completed but no response was returned")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    } else {
      ContentUnavailableView(
        "No Response",
        systemImage: "function",
        description: Text("Enter arguments and click the ▶ button to call the tool")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var shouldShowCopyButton: Bool {
    // Show copy button if we have raw JSON or if there's an error
    responseJSON != nil || responseError != nil
  }

  private func copyRawDataToClipboard() {
    RawDataView.copyRawDataToClipboard(
      responseJSON: responseJSON,
      responseError: responseError
    )
  }
}

