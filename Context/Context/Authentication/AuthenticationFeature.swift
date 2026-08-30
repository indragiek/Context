// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Dependencies
import Foundation
import os

@Reducer
struct AuthenticationFeature {
  @ObservableState
  struct State: Equatable {
    let serverID: UUID
    let serverName: String
    let serverURL: URL
    let resourceMetadataURL: URL
    let expiredToken: OAuthToken?

    var isLoading: Bool = false
    var authorizationURL: URL?
    var pkceParameters: OAuthClient.PKCEParameters?
    var pendingAuthorizationCode: String?
    var error: String?
    var authServerMetadata: AuthorizationServerMetadata?
    var resourceMetadata: ProtectedResourceMetadata?

    // OAuth parameters
    var clientID = "com.indragie.Context"  // Made mutable for dynamic registration
    let redirectURI = OAuthConstants.callbackURL.absoluteString
    var oAuthState: OAuthClient.StateParameter?  // Generated fresh for each auth attempt
    var isRegisteredClient: Bool = false  // Track if we've dynamically registered
    var hasAttemptedLateClientRegistration: Bool = false

    // Loading state tracking
    var loadingStep: LoadingStep = .idle
    var showSuccessAnimation: Bool = false
    var isSilentRefresh: Bool = false
    var authenticationCompleted: Bool = false  // Track if auth completed successfully
    var isRefreshing: Bool = false  // Prevent concurrent refresh attempts
    var showRefreshError: Bool = false  // Show refresh error with Continue button

    enum LoadingStep: String, CaseIterable {
      case idle = ""
      case connectingToServer = "Connecting to server..."
      case discoveringAuth = "Discovering authentication service..."
      case preparingAuth = "Preparing secure authentication..."
      case openingBrowser = "Opening browser..."
      case waitingForUser = "Complete authentication in your browser..."
      case exchangingToken = "Completing authentication..."
      case storingCredentials = "Securing your credentials..."
      case refreshingToken = "Refreshing authentication..."
    }

    init(
      serverID: UUID,
      serverName: String,
      serverURL: URL,
      resourceMetadataURL: URL,
      expiredToken: OAuthToken? = nil,
      clientID: String? = nil
    ) {
      self.serverID = serverID
      self.serverName = serverName
      self.serverURL = serverURL
      self.resourceMetadataURL = resourceMetadataURL
      self.expiredToken = expiredToken
      // Use provided clientID or default
      if let clientID = clientID {
        self.clientID = clientID
      }
    }
  }

  enum ClientRegistrationPurpose: Sendable {
    case beforeAuthorization
    case invalidClientRecovery
  }

  enum Action {
    case startAuthentication
    case metadataLoaded(
      resource: ProtectedResourceMetadata?, authServer: AuthorizationServerMetadata)
    case metadataLoadFailed(any Error)
    case authorizationURLPrepared(URL, OAuthClient.PKCEParameters)
    case browserOpened
    case authorizationCompleted(code: String, state: String)
    case tokenExchangeCompleted(Result<OAuthToken, any Error>)
    case refreshToken(OAuthToken)
    case tokenRefreshCompleted(Result<OAuthToken, any Error>)
    case cancelButtonTapped
    case dismissError
    case attemptClientRegistration
    case clientRegistrationCompleted(
      Result<ClientRegistrationResponse, any Error>, purpose: ClientRegistrationPurpose)
    case authenticationCompleteAndDismiss
    case continueAfterRefreshError
  }

  @Dependency(\.dismiss) var dismiss
  @Dependency(\.mcpClientManager) var clientManager
  @Dependency(\.oauthClient) var oauthClient
  @Dependency(\.oauthTransactionGenerator) var transactionGenerator

  private let logger = Logger(subsystem: "com.indragie.Context", category: "AuthenticationFeature")

  private enum CancelID {
    case authenticationFlow
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .startAuthentication:
        return handleStartAuthentication(&state)

      case let .metadataLoaded(resourceMetadata, authServerMetadata):
        return handleMetadataLoaded(
          &state, resourceMetadata: resourceMetadata, authServerMetadata: authServerMetadata)

      case let .metadataLoadFailed(error):
        return handleMetadataLoadFailed(&state, error: error)

      case let .authorizationURLPrepared(url, pkce):
        return handleAuthorizationURLPrepared(&state, url: url, pkce: pkce)

      case .browserOpened:
        state.loadingStep = .waitingForUser
        state.isLoading = true
        return .none

      case let .authorizationCompleted(code, returnedState):
        return handleAuthorizationCompleted(&state, code: code, returnedState: returnedState)

      case let .tokenExchangeCompleted(result):
        return handleTokenExchangeCompleted(&state, result: result)

      case let .refreshToken(expiredToken):
        return handleRefreshToken(&state, expiredToken: expiredToken)

      case let .tokenRefreshCompleted(result):
        return handleTokenRefreshCompleted(&state, result: result)

      case .cancelButtonTapped:
        clearAuthorizationTransaction(&state)
        state.authServerMetadata = nil
        state.resourceMetadata = nil
        state.loadingStep = .idle
        state.isLoading = false
        state.isSilentRefresh = false
        state.isRefreshing = false
        state.showSuccessAnimation = false
        return .merge(
          .cancel(id: CancelID.authenticationFlow),
          .run { _ in await dismiss() }
        )

      case .dismissError:
        state.error = nil
        state.loadingStep = .idle
        state.isLoading = false
        state.isRefreshing = false
        state.isSilentRefresh = false
        state.showRefreshError = false
        return .none

      case .attemptClientRegistration:
        return handleAttemptClientRegistration(&state)

      case let .clientRegistrationCompleted(result, purpose):
        return handleClientRegistrationCompleted(&state, result: result, purpose: purpose)

      case .authenticationCompleteAndDismiss:
        // Use TCA's proper dismissal mechanism
        return .run { _ in
          await dismiss()
        }

      case .continueAfterRefreshError:
        state.error = nil
        state.showRefreshError = false
        state.loadingStep = .idle
        state.isLoading = false
        state.isRefreshing = false
        state.isSilentRefresh = false
        return .send(.startAuthentication)
      }
    }
  }

  // MARK: - Action Handlers

  private func setError(_ state: inout State, _ message: String) {
    state.error = message
    state.isLoading = false
    state.loadingStep = .idle
    state.isRefreshing = false
    state.isSilentRefresh = false
    // Clear the authorization transaction on any terminal error.
    clearAuthorizationTransaction(&state)
  }

  private func clearAuthorizationTransaction(_ state: inout State) {
    state.pendingAuthorizationCode = nil
    state.oAuthState = nil
    state.pkceParameters = nil
    state.authorizationURL = nil
  }

  private func createRegistrationRequest(redirectURI: String) -> ClientRegistrationRequest {
    ClientRegistrationRequest(
      redirectUris: [redirectURI],
      clientName: "Context MCP Client",
      scope: nil,
      grantTypes: ["authorization_code", "refresh_token"],
      responseTypes: ["code"],
      tokenEndpointAuthMethod: "none",
      softwareId: "com.indragie.Context",
      softwareVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String
    )
  }

  private func storeTokenAndComplete(
    _ state: inout State, token: OAuthToken, isSilent: Bool = false
  ) -> EffectOf<Self> {
    if !isSilent {
      state.showSuccessAnimation = true
      state.authenticationCompleted = true
      state.isLoading = false
      state.loadingStep = .idle
    }

    return .run {
      [serverID = state.serverID, serverName = state.serverName, clientID = state.clientID] send in
      let mcpServer = MCPServer(
        id: serverID,
        name: serverName,
        transport: .streamableHTTP
      )
      do {
        try await clientManager.storeToken(for: mcpServer, token: token, clientID: clientID)
        // Don't log token operations during silent refresh to avoid information leaks
        if !isSilent {
          logger.info("Successfully completed authentication")
        }

        if isSilent {
          await dismiss()
        } else {
          try? await Task.sleep(for: .seconds(1))
          await send(.authenticationCompleteAndDismiss)
        }
      } catch {
        logger.error("Failed to store credentials")
        await send(.metadataLoadFailed(AuthenticationError.tokenStorageFailed))
      }
    }
  }

  private func handleStartAuthentication(_ state: inout State) -> EffectOf<Self> {
    state.isLoading = true
    state.error = nil
    state.loadingStep = .connectingToServer
    state.hasAttemptedLateClientRegistration = false
    clearAuthorizationTransaction(&state)

    // Generate fresh state for this authentication attempt
    do {
      state.oAuthState = try transactionGenerator.generateState()
    } catch let error as OAuthClientError {
      // Provide specific error message based on the error type
      switch error {
      case .randomGenerationFailed:
        setError(&state, "Unable to generate secure random data. This may indicate a system security issue.")
      default:
        setError(&state, error.errorDescription ?? "Failed to initialize authentication")
      }
      return .none
    } catch {
      setError(&state, "Unexpected error during authentication initialization: \(error.localizedDescription)")
      return .none
    }

    let discovery: EffectOf<Self> = .run { [resourceMetadataURL = state.resourceMetadataURL] send in
      do {
        let (resourceMetadata, authServerMetadata) = try await oauthClient.discoverMetadata(
          resourceMetadataURL: resourceMetadataURL
        )
        guard !Task.isCancelled else { return }
        await send(.metadataLoaded(resource: resourceMetadata, authServer: authServerMetadata))
      } catch {
        guard !Task.isCancelled else { return }
        await send(.metadataLoadFailed(error))
      }
    }
    .cancellable(id: CancelID.authenticationFlow)

    return .concatenate(
      .cancel(id: CancelID.authenticationFlow),
      discovery
    )
  }

  private func handleMetadataLoaded(
    _ state: inout State, resourceMetadata: ProtectedResourceMetadata?,
    authServerMetadata: AuthorizationServerMetadata
  ) -> EffectOf<Self> {
    state.resourceMetadata = resourceMetadata
    state.authServerMetadata = authServerMetadata
    state.loadingStep = .discoveringAuth

    // Check if we need to register the client first
    if authServerMetadata.registrationEndpoint != nil && !state.isRegisteredClient {
      // Attempt dynamic client registration before starting OAuth flow
      logger.info("Registration endpoint available, attempting dynamic client registration")

      return .run { [redirectURI = state.redirectURI] send in
        do {
          let registrationRequest = createRegistrationRequest(redirectURI: redirectURI)

          let response = try await oauthClient.registerClient(
            authServerMetadata: authServerMetadata,
            registrationRequest: registrationRequest
          )

          guard !Task.isCancelled else { return }
          await send(
            .clientRegistrationCompleted(.success(response), purpose: .beforeAuthorization))
        } catch {
          guard !Task.isCancelled else { return }
          // If registration fails, we'll try with the default client ID
          logger.warning("Client registration failed, will attempt with default client ID")
          await send(
            .clientRegistrationCompleted(.failure(error), purpose: .beforeAuthorization))
        }
      }
      .cancellable(id: CancelID.authenticationFlow)
    }

    // If no registration endpoint or already registered, proceed with authorization
    return prepareAuthorizationURL(&state)
  }

  private func prepareAuthorizationURL(_ state: inout State) -> EffectOf<Self> {
    state.loadingStep = .preparingAuth

    // Generate PKCE parameters
    let pkceParameters: OAuthClient.PKCEParameters
    do {
      pkceParameters = try transactionGenerator.generatePKCE()
    } catch let error as OAuthClientError {
      // Provide specific error message based on the error type
      switch error {
      case .randomGenerationFailed:
        setError(&state, "Unable to generate secure authentication challenge. This may indicate a system security issue.")
      default:
        setError(&state, error.errorDescription ?? "Failed to prepare authentication")
      }
      return .none
    } catch {
      setError(&state, "Unexpected error preparing authentication: \(error.localizedDescription)")
      return .none
    }
    state.pkceParameters = pkceParameters

    // Ensure we have a state parameter for CSRF protection
    guard let stateParam = state.oAuthState else {
      setError(&state, "Missing OAuth state parameter")
      return .none
    }

    guard let authServerMetadata = state.authServerMetadata else {
      setError(&state, "Missing authorization server metadata")
      return .none
    }

    do {
      let authURL = try oauthClient.buildAuthorizationURL(
        authServerMetadata: authServerMetadata,
        clientID: state.clientID,
        redirectURI: state.redirectURI,
        pkce: pkceParameters,
        state: stateParam,
        resource: state.resourceMetadata?.resource
      )

      state.authorizationURL = authURL
      state.isLoading = false
      state.loadingStep = .openingBrowser
    } catch {
      logger.error("Failed to build authorization URL")
      setError(&state, "Failed to prepare authorization request")
    }

    return .none
  }

  private func handleMetadataLoadFailed(_ state: inout State, error: any Error) -> EffectOf<Self> {
    setError(&state, error.localizedDescription)
    return .none
  }

  private func handleAuthorizationURLPrepared(
    _ state: inout State, url: URL, pkce: OAuthClient.PKCEParameters
  ) -> EffectOf<Self> {
    state.authorizationURL = url
    state.pkceParameters = pkce
    state.isLoading = false
    return .none
  }

  private func handleAuthorizationCompleted(
    _ state: inout State, code: String, returnedState: String
  ) -> EffectOf<Self> {
    state.loadingStep = .exchangingToken

    // Verify state parameter to prevent CSRF
    guard let expectedState = state.oAuthState,
      returnedState == expectedState.value
    else {
      logger.error("State parameter mismatch - possible CSRF attack")
      setError(&state, "Invalid state parameter - possible security issue")
      return .none
    }

    // Check if state has expired
    guard !expectedState.isExpired else {
      logger.error("State parameter expired")
      setError(&state, "Authentication session expired - please try again")
      return .none
    }

    // Validate authorization code format (basic check)
    guard !code.isEmpty, code.count < 2048 else {
      logger.error("Invalid authorization code format")
      setError(&state, "Invalid authorization code received")
      return .none
    }

    // Consume the state and retain the code only while this exchange is pending.
    state.oAuthState = nil
    state.authorizationURL = nil
    state.pendingAuthorizationCode = code
    state.isLoading = true

    guard let authServerMetadata = state.authServerMetadata,
      let pkceParameters = state.pkceParameters
    else {
      setError(&state, "Missing authentication metadata")
      return .none
    }

    // Clear PKCE parameters immediately after capturing for use
    state.pkceParameters = nil

    return .run {
      [
        clientID = state.clientID,
        redirectURI = state.redirectURI,
        resourceMetadata = state.resourceMetadata,
        canAttemptLateRegistration = !state.hasAttemptedLateClientRegistration
      ] send in
      do {
        let token = try await oauthClient.exchangeCodeForToken(
          code: code,
          authServerMetadata: authServerMetadata,
          clientID: clientID,
          redirectURI: redirectURI,
          pkce: pkceParameters,
          resource: resourceMetadata?.resource
        )
        await send(.tokenExchangeCompleted(.success(token)))
      } catch {
        // Check if it's an OAuth error response with invalid_client
        if let oauthError = error as? OAuthErrorResponse,
          oauthError.error == "invalid_client",
          authServerMetadata.registrationEndpoint != nil,
          canAttemptLateRegistration
        {
          guard !Task.isCancelled else { return }
          await send(.attemptClientRegistration)
        } else {
          guard !Task.isCancelled else { return }
          await send(.tokenExchangeCompleted(.failure(error)))
        }
      }
    }
    .cancellable(id: CancelID.authenticationFlow)
  }

  private func handleTokenExchangeCompleted(
    _ state: inout State, result: Result<OAuthToken, any Error>
  ) -> EffectOf<Self> {
    clearAuthorizationTransaction(&state)

    switch result {
    case let .success(token):
      return storeTokenAndComplete(&state, token: token)

    case let .failure(error):
      logger.error("Token exchange failed")

      if let oauthError = error as? OAuthClientError {
        setError(&state, oauthError.errorDescription ?? "Authentication failed")
      } else if let oauthError = error as? OAuthErrorResponse {
        setError(&state, oauthError.errorDescription ?? "Authentication failed")
      } else {
        setError(&state, "Failed to complete authentication")
      }
      return .none
    }
  }

  private func handleRefreshToken(_ state: inout State, expiredToken: OAuthToken) -> EffectOf<Self>
  {
    // Check if we have a refresh token
    guard let refreshToken = expiredToken.refreshToken else {
      logger.info("No refresh token available, falling back to full authentication")
      state.isSilentRefresh = false
      return .send(.startAuthentication)
    }

    // Prevent concurrent refresh attempts
    guard !state.isRefreshing else {
      logger.warning("Token refresh already in progress, ignoring duplicate request")
      return .none
    }

    state.isLoading = true
    state.isSilentRefresh = true
    state.isRefreshing = true
    state.loadingStep = .refreshingToken

    // We need to discover metadata first since it's not available when refreshing
    return .run {
      [
        clientID = state.clientID,
        resourceMetadataURL = state.resourceMetadataURL
      ] send in
      do {
        logger.info("Discovering metadata for token refresh")

        // First, discover the metadata
        let (resourceMetadata, authServerMetadata) = try await oauthClient.discoverMetadata(
          resourceMetadataURL: resourceMetadataURL
        )

        logger.info("Metadata discovered, attempting token refresh")

        // Now attempt the refresh with the discovered metadata
        let newToken = try await oauthClient.refreshToken(
          refreshToken: refreshToken,
          authServerMetadata: authServerMetadata,
          clientID: clientID,
          resource: resourceMetadata?.resource
        )

        logger.debug("Authentication refresh completed")
        guard !Task.isCancelled else { return }
        await send(.tokenRefreshCompleted(.success(newToken)))
      } catch {
        guard !Task.isCancelled else { return }
        logger.error("Authentication refresh failed: \(error.localizedDescription)")
        await send(.tokenRefreshCompleted(.failure(error)))
      }
    }
    .cancellable(id: CancelID.authenticationFlow)
  }

  private func handleTokenRefreshCompleted(
    _ state: inout State, result: Result<OAuthToken, any Error>
  ) -> EffectOf<Self> {
    state.isLoading = false
    state.loadingStep = .idle
    state.isRefreshing = false  // Reset refresh flag

    switch result {
    case let .success(token):
      let isSilentRefresh = state.isSilentRefresh
      return storeTokenAndComplete(&state, token: token, isSilent: isSilentRefresh)

    case let .failure(error):
      logger.error("Token refresh failed, falling back to full authentication: \(error)")

      // If it was a metadata discovery error, show a specific message
      if error is URLError {
        state.error =
          "Unable to connect to authentication server. Please check your network connection."
      } else if let oauthError = error as? OAuthErrorResponse {
        // Handle specific OAuth errors (e.g., invalid_grant when refresh token is revoked)
        if oauthError.error == "invalid_grant" {
          logger.info("Refresh token invalid or expired, requiring re-authentication")
        }
        state.error = oauthError.errorDescription ?? "Authentication refresh failed"
      } else {
        state.error = "Failed to refresh authentication. Please sign in again."
      }

      // Show refresh error with Continue button
      state.isSilentRefresh = false
      state.isLoading = false
      state.showRefreshError = true

      return .none  // Wait for user to click Continue
    }
  }

  private func handleAttemptClientRegistration(_ state: inout State) -> EffectOf<Self> {
    // The rejected code, state, and verifier belong to the old client and can never be reused.
    clearAuthorizationTransaction(&state)

    guard !state.hasAttemptedLateClientRegistration else {
      setError(
        &state, "The authorization server rejected the registered OAuth client (invalid_client).")
      return .none
    }

    guard let authServerMetadata = state.authServerMetadata else {
      setError(&state, "Missing authentication metadata for registration")
      return .none
    }

    state.hasAttemptedLateClientRegistration = true
    state.isLoading = true
    state.error = nil
    state.loadingStep = .discoveringAuth

    let registrationRequest = createRegistrationRequest(redirectURI: state.redirectURI)

    return .run { send in
      do {
        let registrationResponse = try await oauthClient.registerClient(
          authServerMetadata: authServerMetadata,
          registrationRequest: registrationRequest
        )
        guard !Task.isCancelled else { return }
        await send(
          .clientRegistrationCompleted(
            .success(registrationResponse), purpose: .invalidClientRecovery))
      } catch {
        guard !Task.isCancelled else { return }
        await send(
          .clientRegistrationCompleted(.failure(error), purpose: .invalidClientRecovery))
      }
    }
    .cancellable(id: CancelID.authenticationFlow)
  }

  private func handleClientRegistrationCompleted(
    _ state: inout State, result: Result<ClientRegistrationResponse, any Error>,
    purpose: ClientRegistrationPurpose
  ) -> EffectOf<Self> {
    switch result {
    case let .success(registrationResponse):
      logger.info("Successfully registered client with ID: \(registrationResponse.clientId)")

      state.clientID = registrationResponse.clientId
      state.isRegisteredClient = true

      switch purpose {
      case .beforeAuthorization:
        // The state created when authentication started is still valid.
        return prepareAuthorizationURL(&state)

      case .invalidClientRecovery:
        // Registration changed the client identity. Start a wholly new authorization transaction;
        // an authorization code and verifier issued to the old client must not cross this boundary.
        clearAuthorizationTransaction(&state)
        do {
          state.oAuthState = try transactionGenerator.generateState()
        } catch let error as OAuthClientError {
          setError(&state, error.errorDescription ?? "Failed to restart authentication")
          return .none
        } catch {
          setError(
            &state, "Unexpected error restarting authentication: \(error.localizedDescription)")
          return .none
        }
        return prepareAuthorizationURL(&state)
      }

    case let .failure(error):
      logger.error("Client registration failed")

      switch purpose {
      case .beforeAuthorization:
        // Initial registration is opportunistic. Preserve the existing fallback to the default ID.
        logger.warning("Pre-authorization registration failed, proceeding with default client ID")
        return prepareAuthorizationURL(&state)

      case .invalidClientRecovery:
        if let oauthError = error as? OAuthClientError {
          setError(&state, "Registration failed: \(oauthError.errorDescription ?? "Unknown error")")
        } else {
          setError(&state, "Failed to register client with authorization server")
        }
        return .none
      }
    }
  }
}
