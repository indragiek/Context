// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Foundation
import Testing

@testable import Context

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AuthenticationFeatureTests {
  @Test func invalidClientRegistrationStartsFreshAuthorizationTransaction() async throws {
    let recorder = OAuthRequestRecorder()
    let session = makeSession()
    let oauthClient = OAuthClient(urlSession: session)
    let metadata = try makeMetadata()
    let original = try makeReadyTransaction(clientID: "original-client", metadata: metadata)
    let freshState = try OAuthClient.StateParameter.generate()
    let freshPKCE = try OAuthClient.PKCEParameters.generate()
    let freshAuthorizationURL = try oauthClient.buildAuthorizationURL(
      authServerMetadata: metadata,
      clientID: "registered-client",
      redirectURI: original.state.redirectURI,
      pkce: freshPKCE,
      state: freshState,
      resource: nil
    )

    #expect(freshState.value != original.stateParameter.value)
    #expect(freshPKCE.verifier != original.pkce.verifier)

    AuthenticationURLProtocol.requestHandler = { request, protocolInstance in
      let ordinal = recorder.record(request)
      switch request.url?.path {
      case "/token" where ordinal == 1:
        protocolInstance.respond(statusCode: 400, json: #"{"error":"invalid_client"}"#)
      case "/register":
        protocolInstance.respond(
          statusCode: 201,
          json: #"{"client_id":"registered-client","token_endpoint_auth_method":"none"}"#
        )
      case "/token" where ordinal == 2:
        // A terminal response keeps this test focused on the two requests without storing a token.
        protocolInstance.respond(statusCode: 400, json: #"{"error":"invalid_grant"}"#)
      default:
        protocolInstance.fail(UnexpectedRequestError(request.url))
      }
    }
    defer { AuthenticationURLProtocol.reset() }

    let store = makeStore(
      state: original.state,
      oauthClient: oauthClient,
      generatedState: freshState,
      generatedPKCE: freshPKCE
    )

    await store.send(
      .authorizationCompleted(code: "original-code", state: original.stateParameter.value)
    ) {
      $0.loadingStep = .exchangingToken
      $0.oAuthState = nil
      $0.authorizationURL = nil
      $0.pendingAuthorizationCode = "original-code"
      $0.isLoading = true
      $0.pkceParameters = nil
    }

    await store.receive {
      guard case .attemptClientRegistration = $0 else { return false }
      return true
    } assert: {
      $0.pendingAuthorizationCode = nil
      $0.hasAttemptedLateClientRegistration = true
      $0.loadingStep = .discoveringAuth
    }

    await store.receive {
      guard case let .clientRegistrationCompleted(.success(response), purpose) = $0,
        case .invalidClientRecovery = purpose
      else { return false }
      return response.clientId == "registered-client"
    } assert: {
      $0.clientID = "registered-client"
      $0.isRegisteredClient = true
      $0.oAuthState = freshState
      $0.pkceParameters = freshPKCE
      $0.authorizationURL = freshAuthorizationURL
      $0.isLoading = false
      $0.loadingStep = .openingBrowser
    }

    #expect(store.state.error == nil)
    #expect(store.state.pendingAuthorizationCode == nil)
    #expect(queryItems(in: store.state.authorizationURL)["client_id"] == "registered-client")
    #expect(queryItems(in: store.state.authorizationURL)["state"] == freshState.value)
    #expect(queryItems(in: store.state.authorizationURL)["code_challenge"] == freshPKCE.challenge)
    #expect(queryItems(in: store.state.authorizationURL)["error"] == nil)

    await store.send(.authorizationCompleted(code: "fresh-code", state: freshState.value)) {
      $0.loadingStep = .exchangingToken
      $0.oAuthState = nil
      $0.authorizationURL = nil
      $0.pendingAuthorizationCode = "fresh-code"
      $0.isLoading = true
      $0.pkceParameters = nil
    }

    await store.receive {
      guard case let .tokenExchangeCompleted(.failure(error)) = $0,
        let response = error as? OAuthErrorResponse
      else { return false }
      return response.error == "invalid_grant"
    } assert: {
      $0.pendingAuthorizationCode = nil
      $0.error = "invalid_grant"
      $0.isLoading = false
      $0.loadingStep = .idle
    }

    await store.finish()

    let tokenRequests = recorder.requests(path: "/token")
    let registrationRequests = recorder.requests(path: "/register")
    #expect(tokenRequests.count == 2)
    #expect(registrationRequests.count == 1)
    #expect(tokenRequests[0].formParameters["code"] == "original-code")
    #expect(tokenRequests[0].formParameters["client_id"] == "original-client")
    #expect(tokenRequests[0].formParameters["code_verifier"] == original.pkce.verifier)
    #expect(tokenRequests[1].formParameters["code"] == "fresh-code")
    #expect(tokenRequests[1].formParameters["client_id"] == "registered-client")
    #expect(tokenRequests[1].formParameters["code_verifier"] == freshPKCE.verifier)
    #expect(
      !tokenRequests.contains {
        $0.formParameters["code"] == "original-code"
          && $0.formParameters["client_id"] == "registered-client"
      })
  }

  @Test func repeatedInvalidClientIsTerminalWithoutAnotherRegistration() async throws {
    let recorder = OAuthRequestRecorder()
    let oauthClient = OAuthClient(urlSession: makeSession())
    let metadata = try makeMetadata()
    var transaction = try makeReadyTransaction(clientID: "registered-client", metadata: metadata)
    transaction.state.isRegisteredClient = true
    transaction.state.hasAttemptedLateClientRegistration = true

    AuthenticationURLProtocol.requestHandler = { request, protocolInstance in
      _ = recorder.record(request)
      if request.url?.path == "/token" {
        protocolInstance.respond(statusCode: 400, json: #"{"error":"invalid_client"}"#)
      } else {
        protocolInstance.fail(UnexpectedRequestError(request.url))
      }
    }
    defer { AuthenticationURLProtocol.reset() }

    let store = makeStore(state: transaction.state, oauthClient: oauthClient)

    await store.send(
      .authorizationCompleted(code: "second-code", state: transaction.stateParameter.value)
    ) {
      $0.loadingStep = .exchangingToken
      $0.oAuthState = nil
      $0.authorizationURL = nil
      $0.pendingAuthorizationCode = "second-code"
      $0.isLoading = true
      $0.pkceParameters = nil
    }

    await store.receive {
      guard case let .tokenExchangeCompleted(.failure(error)) = $0,
        let response = error as? OAuthErrorResponse
      else { return false }
      return response.error == "invalid_client"
    } assert: {
      $0.pendingAuthorizationCode = nil
      $0.error = "invalid_client"
      $0.isLoading = false
      $0.loadingStep = .idle
    }

    await store.finish()
    assertTransactionCleared(store.state)
    #expect(store.state.hasAttemptedLateClientRegistration)
    #expect(recorder.requests(path: "/token").count == 1)
    #expect(recorder.requests(path: "/register").isEmpty)
  }

  @Test func lateRegistrationFailureIsTerminalAndClearsTransaction() async throws {
    let recorder = OAuthRequestRecorder()
    let oauthClient = OAuthClient(urlSession: makeSession())
    let metadata = try makeMetadata()
    let transaction = try makeReadyTransaction(clientID: "original-client", metadata: metadata)

    AuthenticationURLProtocol.requestHandler = { request, protocolInstance in
      _ = recorder.record(request)
      switch request.url?.path {
      case "/token":
        protocolInstance.respond(statusCode: 400, json: #"{"error":"invalid_client"}"#)
      case "/register":
        protocolInstance.respond(
          statusCode: 400,
          json: #"{"error":"invalid_client_metadata","error_description":"rejected"}"#
        )
      default:
        protocolInstance.fail(UnexpectedRequestError(request.url))
      }
    }
    defer { AuthenticationURLProtocol.reset() }

    let store = makeStore(state: transaction.state, oauthClient: oauthClient)

    await store.send(
      .authorizationCompleted(code: "rejected-code", state: transaction.stateParameter.value)
    ) {
      $0.loadingStep = .exchangingToken
      $0.oAuthState = nil
      $0.authorizationURL = nil
      $0.pendingAuthorizationCode = "rejected-code"
      $0.isLoading = true
      $0.pkceParameters = nil
    }

    await store.receive {
      guard case .attemptClientRegistration = $0 else { return false }
      return true
    } assert: {
      $0.pendingAuthorizationCode = nil
      $0.hasAttemptedLateClientRegistration = true
      $0.loadingStep = .discoveringAuth
    }

    await store.receive {
      guard case let .clientRegistrationCompleted(.failure, purpose) = $0,
        case .invalidClientRecovery = purpose
      else { return false }
      return true
    } assert: {
      $0.error = "Registration failed: invalid_client_metadata: rejected"
      $0.isLoading = false
      $0.loadingStep = .idle
    }

    await store.finish()
    assertTransactionCleared(store.state)
    #expect(recorder.requests(path: "/register").count == 1)
    #expect(recorder.requests(path: "/token").count == 1)
  }

  @Test func terminalTokenFailureClearsTransactionAndStopsLoading() async throws {
    let recorder = OAuthRequestRecorder()
    let oauthClient = OAuthClient(urlSession: makeSession())
    let metadata = try makeMetadata()
    let transaction = try makeReadyTransaction(clientID: "original-client", metadata: metadata)

    AuthenticationURLProtocol.requestHandler = { request, protocolInstance in
      _ = recorder.record(request)
      if request.url?.path == "/token" {
        protocolInstance.respond(
          statusCode: 400,
          json: #"{"error":"invalid_grant","error_description":"expired"}"#
        )
      } else {
        protocolInstance.fail(UnexpectedRequestError(request.url))
      }
    }
    defer { AuthenticationURLProtocol.reset() }

    let store = makeStore(state: transaction.state, oauthClient: oauthClient)

    await store.send(
      .authorizationCompleted(code: "expired-code", state: transaction.stateParameter.value)
    ) {
      $0.loadingStep = .exchangingToken
      $0.oAuthState = nil
      $0.authorizationURL = nil
      $0.pendingAuthorizationCode = "expired-code"
      $0.isLoading = true
      $0.pkceParameters = nil
    }

    await store.receive {
      guard case let .tokenExchangeCompleted(.failure(error)) = $0,
        let response = error as? OAuthErrorResponse
      else { return false }
      return response.error == "invalid_grant"
    } assert: {
      $0.pendingAuthorizationCode = nil
      $0.error = "invalid_grant: expired"
      $0.isLoading = false
      $0.loadingStep = .idle
    }

    await store.finish()
    assertTransactionCleared(store.state)
    #expect(recorder.requests(path: "/token").count == 1)
    #expect(recorder.requests(path: "/register").isEmpty)
  }

  @Test func cancellationClearsPendingExchangeAndCancelsNetworkEffect() async throws {
    let recorder = OAuthRequestRecorder()
    let oauthClient = OAuthClient(urlSession: makeSession())
    let metadata = try makeMetadata()
    let transaction = try makeReadyTransaction(clientID: "original-client", metadata: metadata)

    AuthenticationURLProtocol.requestHandler = { request, _ in
      _ = recorder.record(request)
      // Deliberately leave the token response pending. Cancelling the reducer effect must stop it.
    }
    defer { AuthenticationURLProtocol.reset() }

    let store = makeStore(state: transaction.state, oauthClient: oauthClient)

    await store.send(
      .authorizationCompleted(code: "pending-code", state: transaction.stateParameter.value)
    ) {
      $0.loadingStep = .exchangingToken
      $0.oAuthState = nil
      $0.authorizationURL = nil
      $0.pendingAuthorizationCode = "pending-code"
      $0.isLoading = true
      $0.pkceParameters = nil
    }

    let tokenRequestStarted = await waitUntil { recorder.requests(path: "/token").count == 1 }
    #expect(tokenRequestStarted)

    await store.send(.cancelButtonTapped) {
      $0.pendingAuthorizationCode = nil
      $0.authServerMetadata = nil
      $0.resourceMetadata = nil
      $0.loadingStep = .idle
      $0.isLoading = false
      $0.isSilentRefresh = false
      $0.isRefreshing = false
      $0.showSuccessAnimation = false
    }

    await store.finish()
    assertTransactionCleared(store.state)
    #expect(recorder.requests(path: "/token").count == 1)
    #expect(recorder.requests(path: "/register").isEmpty)
  }

  @Test func successfulPreAuthorizationRegistrationStillBuildsAuthorizationURL() async throws {
    let recorder = OAuthRequestRecorder()
    let oauthClient = OAuthClient(urlSession: makeSession())
    let metadata = try makeMetadata()
    let stateParameter = try OAuthClient.StateParameter.generate()
    let pkce = try OAuthClient.PKCEParameters.generate()
    var initialState = makeState(clientID: "original-client")
    initialState.oAuthState = stateParameter
    initialState.isLoading = true
    initialState.loadingStep = .connectingToServer
    let expectedURL = try oauthClient.buildAuthorizationURL(
      authServerMetadata: metadata,
      clientID: "registered-client",
      redirectURI: initialState.redirectURI,
      pkce: pkce,
      state: stateParameter,
      resource: nil
    )

    AuthenticationURLProtocol.requestHandler = { request, protocolInstance in
      _ = recorder.record(request)
      if request.url?.path == "/register" {
        protocolInstance.respond(statusCode: 201, json: #"{"client_id":"registered-client"}"#)
      } else {
        protocolInstance.fail(UnexpectedRequestError(request.url))
      }
    }
    defer { AuthenticationURLProtocol.reset() }

    let store = makeStore(
      state: initialState,
      oauthClient: oauthClient,
      generatedState: stateParameter,
      generatedPKCE: pkce
    )

    await store.send(.metadataLoaded(resource: nil, authServer: metadata)) {
      $0.authServerMetadata = metadata
      $0.loadingStep = .discoveringAuth
    }

    await store.receive {
      guard case let .clientRegistrationCompleted(.success(response), purpose) = $0,
        case .beforeAuthorization = purpose
      else { return false }
      return response.clientId == "registered-client"
    } assert: {
      $0.clientID = "registered-client"
      $0.isRegisteredClient = true
      $0.pkceParameters = pkce
      $0.authorizationURL = expectedURL
      $0.isLoading = false
      $0.loadingStep = .openingBrowser
    }

    await store.finish()
    #expect(store.state.oAuthState == stateParameter)
    #expect(!store.state.hasAttemptedLateClientRegistration)
    #expect(recorder.requests(path: "/register").count == 1)
    #expect(recorder.requests(path: "/token").isEmpty)
  }

  private func makeStore(
    state: AuthenticationFeature.State,
    oauthClient: OAuthClient,
    generatedState: OAuthClient.StateParameter? = nil,
    generatedPKCE: OAuthClient.PKCEParameters? = nil
  ) -> TestStoreOf<AuthenticationFeature> {
    let fallbackState = generatedState ?? state.oAuthState!
    let fallbackPKCE = generatedPKCE ?? state.pkceParameters!
    return TestStore(initialState: state) {
      AuthenticationFeature()
    } withDependencies: {
      $0.oauthClient = oauthClient
      $0.oauthTransactionGenerator = OAuthTransactionGenerator(
        generateState: { fallbackState },
        generatePKCE: { fallbackPKCE }
      )
      $0.dismiss = DismissEffect {}
    }
  }

  private func makeState(clientID: String) -> AuthenticationFeature.State {
    AuthenticationFeature.State(
      serverID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      serverName: "Test Server",
      serverURL: URL(string: "https://mcp.example.com")!,
      resourceMetadataURL: URL(string: "https://mcp.example.com/.well-known/oauth")!,
      clientID: clientID
    )
  }

  private func makeReadyTransaction(
    clientID: String, metadata: AuthorizationServerMetadata
  ) throws -> ReadyTransaction {
    let stateParameter = try OAuthClient.StateParameter.generate()
    let pkce = try OAuthClient.PKCEParameters.generate()
    var state = makeState(clientID: clientID)
    state.authServerMetadata = metadata
    state.oAuthState = stateParameter
    state.pkceParameters = pkce
    state.authorizationURL = try OAuthClient().buildAuthorizationURL(
      authServerMetadata: metadata,
      clientID: clientID,
      redirectURI: state.redirectURI,
      pkce: pkce,
      state: stateParameter,
      resource: nil
    )
    state.loadingStep = .openingBrowser
    return ReadyTransaction(state: state, stateParameter: stateParameter, pkce: pkce)
  }

  private func makeMetadata() throws -> AuthorizationServerMetadata {
    try JSONDecoder().decode(
      AuthorizationServerMetadata.self,
      from: Data(
        #"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","response_types_supported":["code"],"grant_types_supported":["authorization_code"],"code_challenge_methods_supported":["S256"],"registration_endpoint":"https://auth.example.com/register"}"#.utf8
      )
    )
  }

  private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthenticationURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private func queryItems(in url: URL?) -> [String: String] {
    guard let url,
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return [:] }
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
      item.value.map { (item.name, $0) }
    })
  }

  private func assertTransactionCleared(_ state: AuthenticationFeature.State) {
    #expect(state.pendingAuthorizationCode == nil)
    #expect(state.oAuthState == nil)
    #expect(state.pkceParameters == nil)
    #expect(state.authorizationURL == nil)
    #expect(!state.isLoading)
    #expect(state.loadingStep == .idle)
  }

  private func waitUntil(_ predicate: @escaping @Sendable () -> Bool) async -> Bool {
    for _ in 0..<100 {
      if predicate() { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }
}

private struct ReadyTransaction {
  var state: AuthenticationFeature.State
  let stateParameter: OAuthClient.StateParameter
  let pkce: OAuthClient.PKCEParameters
}

private struct RecordedOAuthRequest: Sendable {
  let path: String
  let formParameters: [String: String]
}

private final class OAuthRequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [RecordedOAuthRequest] = []

  @discardableResult
  func record(_ request: URLRequest) -> Int {
    let recordedRequest = RecordedOAuthRequest(
      path: request.url?.path ?? "",
      formParameters: Self.formParameters(from: request)
    )
    return lock.withLock {
      storage.append(recordedRequest)
      return storage.lazy.filter { $0.path == recordedRequest.path }.count
    }
  }

  func requests(path: String) -> [RecordedOAuthRequest] {
    lock.withLock { storage.filter { $0.path == path } }
  }

  private static func formParameters(from request: URLRequest) -> [String: String] {
    let body = request.httpBody ?? request.httpBodyStream.map(readAllData)
    guard let body,
      let encoded = String(data: body, encoding: .utf8),
      let items = URLComponents(string: "https://example.invalid/?\(encoded)")?.queryItems
    else { return [:] }
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
      item.value.map { (item.name, $0) }
    })
  }

  private static func readAllData(from stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

private struct UnexpectedRequestError: Error {
  let url: URL?

  init(_ url: URL?) {
    self.url = url
  }
}

private final class AuthenticationURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requestHandler:
    ((URLRequest, AuthenticationURLProtocol) -> Void)?

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let requestHandler = Self.requestHandler else {
      fail(UnexpectedRequestError(request.url))
      return
    }
    requestHandler(request, self)
  }

  override func stopLoading() {}

  func respond(statusCode: Int, json: String) {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    else {
      fail(UnexpectedRequestError(request.url))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(json.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  func fail(_ error: any Error) {
    client?.urlProtocol(self, didFailWithError: error)
  }

  static func reset() {
    requestHandler = nil
  }
}
