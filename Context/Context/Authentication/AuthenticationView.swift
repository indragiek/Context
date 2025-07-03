// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AuthenticationServices
import ComposableArchitecture
import ContextCore
import SwiftUI

struct AuthenticationView: View {
  @Bindable var store: StoreOf<AuthenticationFeature>
  @Environment(\.dismiss) private var dismiss
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession

  var body: some View {
    ZStack {
      contentView
    }
    .frame(width: 450, height: 300)
    .onAppear {
      if !store.authenticationCompleted && !store.isRefreshing {
        // Check if we have an expired token with a refresh token
        if let expiredToken = store.expiredToken,
          expiredToken.isExpired,
          expiredToken.refreshToken != nil
        {
          store.send(.refreshToken(expiredToken))
        } else {
          store.send(.startAuthentication)
        }
      }
    }
  }

  @ViewBuilder
  private var contentView: some View {
    if store.showSuccessAnimation || store.authenticationCompleted {
      successView
    } else if store.isLoading {
      loadingView
    } else if let error = store.error {
      if store.showRefreshError {
        refreshErrorView(error: error)
      } else {
        errorView(error: error)
      }
    } else if store.authorizationURL != nil {
      authorizationPromptView
    } else {
      Color(NSColor.windowBackgroundColor)
    }
  }

  private var successView: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 64))
        .foregroundStyle(.green)
        .scaleEffect(1.0)

      Text("Authenticated")
        .font(.title2)
        .fontWeight(.semibold)
    }
    .padding(40)
  }

  private var loadingView: some View {
    VStack(spacing: 20) {
      ProgressView()
        .scaleEffect(1.2)
        .controlSize(.large)

      if !store.loadingStep.rawValue.isEmpty {
        Text(store.loadingStep.rawValue)
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .animation(.easeInOut(duration: 0.3), value: store.loadingStep)
      }

      if !store.isSilentRefresh {
        StepIndicatorView(currentStep: store.loadingStep)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(40)
  }

  private func errorView(error: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundStyle(.orange)

      Text("Authentication Error")
        .font(.title2)
        .fontWeight(.semibold)

      Text(error)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 12) {
        Button("Try Again") {
          store.send(.dismissError)
          store.send(.startAuthentication)
        }
        .controlSize(.large)

        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .controlSize(.large)
        .buttonStyle(.plain)
      }
    }
    .padding(40)
  }

  private var authorizationPromptView: some View {
    VStack(spacing: 16) {
      Image(systemName: "lock.circle.fill")
        .font(.system(size: 48))
        .foregroundStyle(.blue)

      Text("Authentication Required")
        .font(.title2)
        .fontWeight(.semibold)

      Text(
        "The server \"\(store.serverName)\" requires authentication. Click Continue to sign in with your browser."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 12) {
        Button("Continue") {
          startAuthentication()
        }
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)

        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .controlSize(.large)
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
      }
    }
    .padding(40)
  }

  private func refreshErrorView(error: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
        .font(.system(size: 48))
        .foregroundStyle(.orange)

      Text("Authentication Refresh Failed")
        .font(.title2)
        .fontWeight(.semibold)

      Text(error)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text("Click Continue to sign in again with your browser.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      HStack(spacing: 12) {
        Button("Continue") {
          store.send(.continueAfterRefreshError)
        }
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)

        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .controlSize(.large)
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
      }
    }
    .padding(40)
  }

  private func startAuthentication() {
    guard let authURL = store.authorizationURL else { return }

    // Signal that the browser is opening
    store.send(.browserOpened)

    Task {
      do {
        let urlScheme = OAuthConstants.urlScheme
        let result = try await webAuthenticationSession.authenticate(
          using: authURL,
          callbackURLScheme: urlScheme,
          preferredBrowserSession: .shared
        )

        // Validate callback URL structure
        guard result.scheme == urlScheme,
          result.host == OAuthConstants.callbackHost,
          result.path == OAuthConstants.callbackPath
        else {
          store.send(
            .metadataLoadFailed(
              AuthenticationError.invalidCallback("Invalid callback URL structure")
            ))
          return
        }

        // Parse the callback URL
        guard let components = URLComponents(url: result, resolvingAgainstBaseURL: false) else {
          store.send(
            .metadataLoadFailed(
              AuthenticationError.invalidCallback("Failed to parse callback URL")
            ))
          return
        }

        // Extract code and state with validation
        let queryItems = components.queryItems ?? []
        var code: String?
        var state: String?

        for item in queryItems {
          switch item.name {
          case "code":
            code = item.value
          case "state":
            state = item.value
          case "error":
            // Handle OAuth error response
            let errorDescription = queryItems.first(where: { $0.name == "error_description" })?
              .value
            store.send(
              .metadataLoadFailed(
                AuthenticationError.oauthError(
                  error: item.value ?? "unknown",
                  description: errorDescription
                )
              ))
            return
          default:
            break
          }
        }

        guard let authCode = code, !authCode.isEmpty,
          let authState = state, !authState.isEmpty
        else {
          store.send(
            .metadataLoadFailed(
              AuthenticationError.invalidCallback("Missing code or state in callback")
            ))
          return
        }

        store.send(.authorizationCompleted(code: authCode, state: authState))
      } catch {
        // Check if the user cancelled
        if let authError = error as? ASWebAuthenticationSessionError,
          authError.code == .canceledLogin
        {
          store.send(.cancelButtonTapped)
        } else {
          store.send(.metadataLoadFailed(error))
        }
      }
    }
  }
}

// MARK: - Authentication Errors

enum AuthenticationError: LocalizedError {
  case invalidCallback(String)
  case oauthError(error: String, description: String?)
  case storageError(String)

  var errorDescription: String? {
    switch self {
    case .invalidCallback(let reason):
      return "Invalid authentication callback: \(reason)"
    case .oauthError(let error, let description):
      if let description = description {
        return "Authentication failed: \(description)"
      } else {
        return "Authentication failed: \(error)"
      }
    case .storageError(let reason):
      return reason
    }
  }

  static let tokenStorageFailed = AuthenticationError.storageError(
    "Failed to store authentication token")
}

// MARK: - Step Indicator

struct StepIndicatorView: View {
  let currentStep: AuthenticationFeature.State.LoadingStep

  private let steps: [AuthenticationFeature.State.LoadingStep] = [
    .connectingToServer,
    .discoveringAuth,
    .preparingAuth,
    .openingBrowser,
    .waitingForUser,
    .exchangingToken,
    .storingCredentials,
  ]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
        Circle()
          .fill(stepColor(for: step))
          .frame(width: 8, height: 8)
          .scaleEffect(currentStep == step ? 1.2 : 1.0)
          .animation(.easeInOut(duration: 0.3), value: currentStep)
      }
    }
    .padding(.top, 8)
  }

  private func stepColor(for step: AuthenticationFeature.State.LoadingStep) -> Color {
    let currentIndex = steps.firstIndex(of: currentStep) ?? 0
    let stepIndex = steps.firstIndex(of: step) ?? 0

    if stepIndex < currentIndex {
      return .green
    } else if stepIndex == currentIndex {
      return .blue
    } else {
      return .secondary.opacity(0.3)
    }
  }
}

// MARK: - Preview

#Preview {
  AuthenticationView(
    store: Store(
      initialState: AuthenticationFeature.State(
        serverID: UUID(),
        serverName: "Test Server",
        serverURL: URL(string: "https://example.com")!,
        resourceMetadataURL: URL(
          string: "https://example.com/.well-known/oauth-protected-resource")!
      )
    ) {
      AuthenticationFeature()
    }
  )
}
