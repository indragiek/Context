// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// A response that contains no result data.
@JSONRPCResponse
public struct EmptyResponse {
  public struct Result: Codable, Sendable {}
}

/// The sender or recipient of messages and data in a conversation.
public enum Role: String, Codable, Sendable, Equatable {
  case user
  case assistant
}

/// Optional annotations for the client. The client can use annotations to inform
/// how objects are used or displayed.
public struct Annotations: Codable, Sendable, Equatable {
  // TODO: Remove once mock data is removed
  public init(audience: [Role]? = nil, priority: Double? = nil) {
    self.audience = audience
    self.priority = priority
  }

  /// Describes who the intended customer of this object or data is
  ///
  /// It can include multiple entries to indicate content useful for multiple audiences (e.g., `
  /// ["user", "assistant"]`).
  public let audience: [Role]?

  /// Describes how important this data is for operating the server.
  ///
  /// A value of 1 means "most important," and indicates that the data is effectively
  /// required, while 0 means "least important," and indicates that the data is
  /// entirely optional.
  public let priority: Double?
}

/// Base type for resource contents.
public protocol ResourceContents: Codable, Sendable {
  var uri: String { get }
  var mimeType: String? { get }
}

/// Resource contents with text data.
public struct TextResourceContents: ResourceContents, Equatable {
  public let uri: String
  public let mimeType: String?
  public let text: String

  public init(uri: String, mimeType: String? = nil, text: String) {
    self.uri = uri
    self.mimeType = mimeType
    self.text = text
  }
}

/// Resource contents with binary data.
public struct BlobResourceContents: ResourceContents, Equatable {
  public let uri: String
  public let mimeType: String?
  public let blob: Data

  public init(uri: String, mimeType: String? = nil, blob: Data) {
    self.uri = uri
    self.mimeType = mimeType
    self.blob = blob
  }
}

/// Embedded resource content.
public enum EmbeddedResource: Codable, Sendable, Equatable {
  case text(TextResourceContents)
  case blob(BlobResourceContents)

  private enum CodingKeys: String, CodingKey {
    case uri, mimeType, text, blob
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let uri = try container.decode(String.self, forKey: .uri)
    let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)

    if let text = try container.decodeIfPresent(String.self, forKey: .text) {
      self = .text(TextResourceContents(uri: uri, mimeType: mimeType, text: text))
    } else if let blobData = try container.decodeIfPresent(Data.self, forKey: .blob) {
      self = .blob(BlobResourceContents(uri: uri, mimeType: mimeType, blob: blobData))
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .text,
        in: container,
        debugDescription: "Missing text or blob data for resource"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .text(let resource):
      try container.encode(resource.uri, forKey: .uri)
      try container.encodeIfPresent(resource.mimeType, forKey: .mimeType)
      try container.encode(resource.text, forKey: .text)
    case .blob(let resource):
      try container.encode(resource.uri, forKey: .uri)
      try container.encodeIfPresent(resource.mimeType, forKey: .mimeType)
      try container.encode(resource.blob, forKey: .blob)
    }
  }
}

/// LLM content that can be text, image, audio, or an embedded resource.
public enum Content: Codable, Sendable {
  case text(String, annotations: Annotations? = nil)
  case image(data: Data, mimeType: String, annotations: Annotations? = nil)
  case audio(data: Data, mimeType: String, annotations: Annotations? = nil)
  case resource(EmbeddedResource, annotations: Annotations? = nil)

  private enum CodingKeys: String, CodingKey {
    case type
    case text
    case data
    case mimeType
    case annotations
    case resource
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    let annotations = try container.decodeIfPresent(Annotations.self, forKey: .annotations)

    switch type {
    case "text":
      let text = try container.decode(String.self, forKey: .text)
      self = .text(text, annotations: annotations)
    case "image":
      let data = try container.decode(Data.self, forKey: .data)
      let mimeType = try container.decode(String.self, forKey: .mimeType)
      self = .image(data: data, mimeType: mimeType, annotations: annotations)
    case "audio":
      let data = try container.decode(Data.self, forKey: .data)
      let mimeType = try container.decode(String.self, forKey: .mimeType)
      self = .audio(data: data, mimeType: mimeType, annotations: annotations)
    case "resource":
      let resource = try container.decode(EmbeddedResource.self, forKey: .resource)
      self = .resource(resource, annotations: annotations)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unknown content type: \(type)"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .text(let text, let annotations):
      try container.encode("text", forKey: .type)
      try container.encode(text, forKey: .text)
      try container.encodeIfPresent(annotations, forKey: .annotations)
    case .image(let data, let mimeType, let annotations):
      try container.encode("image", forKey: .type)
      try container.encode(data, forKey: .data)
      try container.encode(mimeType, forKey: .mimeType)
      try container.encodeIfPresent(annotations, forKey: .annotations)
    case .audio(let data, let mimeType, let annotations):
      try container.encode("audio", forKey: .type)
      try container.encode(data, forKey: .data)
      try container.encode(mimeType, forKey: .mimeType)
      try container.encodeIfPresent(annotations, forKey: .annotations)
    case .resource(let resource, let annotations):
      try container.encode("resource", forKey: .type)
      try container.encode(resource, forKey: .resource)
      try container.encodeIfPresent(annotations, forKey: .annotations)
    }
  }
}

// MARK: - Initialization

public struct ClientCapabilities: Codable, Sendable, Equatable {
  public struct Roots: Codable, Sendable, Equatable {
    /// Indicates whether the client will emit notifications when the list of
    /// roots changes.
    public let listChanged: Bool

    public init(listChanged: Bool) {
      self.listChanged = listChanged
    }
  }

  /// Supports exposing filesystem roots to servers.
  ///
  /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-03-26/client/roots
  public var roots: Roots?

  public struct Sampling: Codable, Sendable, Equatable {}
  /// Support requesting LLM sampling (completions or generations) from the server.
  ///
  /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-03-26/client/sampling
  public var sampling: Sampling?

  public init() {}
}

public struct ServerCapabilities: Codable, Sendable, Equatable {
  public struct Prompts: Codable, Sendable, Equatable {
    /// Indicates whether the server will emit notifications when the list of
    /// available prompts changes.
    public let listChanged: Bool?
  }

  /// Supports exposing prompt templates to clients.
  ///
  /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-03-26/server/prompts
  public var prompts: Prompts?

  public struct Resources: Codable, Sendable, Equatable {
    /// Indicates whether the client can subscribe to be notified of changes
    /// to individual resources.
    public let subscribe: Bool?

    /// Indicates whether the server will emit notifications when the list of
    /// available resources changes.
    public let listChanged: Bool?
  }

  /// Supports sharing data that provides context to language models, such as
  /// files, database schemas, or application-specific information.
  ///
  /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-03-26/server/resources
  public var resources: Resources?

  public struct Tools: Codable, Sendable, Equatable {
    /// Indicates whether the server will emit notifications when the list of
    /// available tools changes.
    public let listChanged: Bool?
  }

  /// Supports exposing tools that can be invoked by language models.
  ///
  /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-03-26/server/tools
  public var tools: Tools?

  public struct Completions: Codable, Sendable, Equatable {}

  /// Supports argument autocompletion suggestions for prompts and resource URIs.
  ///
  /// - SeeAlso: https://modelcontextprotocol.io/specification/2025-03-26/server/utilities/completion
  public var completions: Completions?

  public struct Logging: Codable, Sendable, Equatable {}

  /// Supports sending structured log messages to clients.
  public var logging: Logging?

  public init() {}
}

/// The name and version of an MCP client or server.
public struct Implementation: Codable, Sendable, Equatable {
  public let name: String
  public let version: String

  public init(name: String, version: String) {
    self.name = name
    self.version = version
  }
}

/// The first request sent by the client to establish a connection with the server.
@JSONRPCRequest(method: "initialize", responseType: InitializeResponse.self)
public struct InitializeRequest {
  public struct Params: Codable, Sendable {
    /// The latest protocol version supported by the client.
    public let protocolVersion: String

    /// Capabilities supported by the client.
    public let capabilities: ClientCapabilities

    /// The name and version of the client.
    public let clientInfo: Implementation
  }
}

/// The result sent by the server in response to `InitializeRequest`
@JSONRPCResponse
public struct InitializeResponse {
  public struct Result: Codable, Sendable {
    /// The protocol version supported by the server, which may be different from
    /// the one requested by the client. If the server supports the requested protocol
    /// version, it must respond with that version; otherwise, this is the latest
    /// protocol version supported by the server.
    public let protocolVersion: String

    /// Capabilities supported by the server.
    public let capabilities: ServerCapabilities

    /// The name and version of the server.
    public let serverInfo: Implementation
  }
}

/// Sent by the client to the server to indicate successful initialization.
@JSONRPCNotification(method: "notifications/initialized")
public struct InitializedNotification {
  public struct Params: Codable, Sendable {}
}

// MARK: - Roots

/// A root directory or location that the client has access to.
public struct Root: Codable, Sendable, Equatable {
  /// A unique `file://` URI identifying the root.
  public let uri: String

  /// An optional human-readable name for display purposes.
  public let name: String?

  public init(uri: String, name: String? = nil) {
    self.uri = uri
    self.name = name
  }
}

/// Request to list the client's roots.
@JSONRPCRequest(method: "roots/list", responseType: ListRootsResponse.self)
public struct ListRootsRequest {
  public struct Params: Codable, Sendable {}
}

/// Response to a `ListRootsRequest`.
@JSONRPCResponse
public struct ListRootsResponse {
  public struct Result: Codable, Sendable {
    /// The list of roots.
    public let roots: [Root]

    public init(roots: [Root]) {
      self.roots = roots
    }
  }
}

/// Notification sent by the client to indicate that the list of roots has changed.
@JSONRPCNotification(method: "notifications/roots/list_changed")
public struct RootsListChangedNotification {
  public struct Params: Codable, Sendable {}
}

// MARK: - Cancellation & Progress

/// Sent by either the client or server to indicate that a request has been cancelled.
@JSONRPCNotification(method: "notifications/cancelled")
public struct CancelledNotification {
  public struct Params: Codable, Sendable {
    /// The ID of the request that was cancelled.
    public let requestId: JSONRPCRequestID

    // An optional cancellation reason that can be logged or displayed.
    public let reason: String?
  }
}

/// Progress notification for long-running requests.
@JSONRPCNotification(method: "notifications/progress")
public struct ProgressNotification {
  public struct Params: Codable, Sendable {
    /// The ID of the request that this progress notification is for.
    public let id: JSONRPCRequestID

    /// A number between 0 and 1 indicating the progress of the request,
    /// where 0 is 0% complete and 1 is 100% complete.
    public let progress: Double?

    /// A human-readable message describing the current state or progress.
    public let message: String?
  }
}

// MARK: - Logging

/// The severity of a log message.
///
/// These map to syslog message severities, as specified in RFC-5424:
/// https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.1
public enum LoggingLevel: String, Codable, Sendable, Equatable {
  /// Detailed debugging information
  case debug
  /// General informational messages
  case info
  /// Normal but significant events
  case notice
  /// Warning conditions
  case warning
  /// Error conditions
  case error
  /// Critical conditions
  case critical
  /// Action must be taken immediately
  case alert
  /// System is unusable
  case emergency
}

/// A request from the client to the server, to enable or adjust logging.
@JSONRPCRequest(method: "logging/setLevel", responseType: EmptyResponse.self)
public struct SetLevelRequest {
  public struct Params: Codable, Sendable {
    /// The level of logging that the client wants to receive from the server.
    /// The server should send all logs at this level and higher (i.e., more severe)
    /// to the client as notifications/message.
    public let level: LoggingLevel
  }
}

/// Notification of a log message passed from server to client. If no
/// logging/setLevel request has been sent from the client, the server MAY decide
/// which messages to send automatically.
@JSONRPCNotification(method: "notifications/message")
public struct LoggingMessageNotification {
  public struct Params: Codable, Sendable, Equatable {
    // TODO: Remove once mock data is no longer being used.
    public init(level: LoggingLevel, logger: String? = nil, data: JSONValue) {
      self.level = level
      self.logger = logger
      self.data = data
    }

    /// The severity of this log message.
    public let level: LoggingLevel

    /// An optional name of the logger issuing this message.
    public let logger: String?

    /// The data to be logged, such as a string message or an object.
    /// Any JSON serializable type is allowed here.
    public let data: JSONValue
  }
}

/// Undocumented notification type that is sent by the `everything` server: https://github.com/modelcontextprotocol/servers/tree/main/src/everything
/// Adding support here so that it doesn't cause a decoding error, but this should either be removed
/// or replaced with `LoggingMessageNotification`
@JSONRPCNotification(method: "notifications/stderr")
public struct StderrNotification {
  public struct Params: Codable, Sendable, Equatable {
    let content: String
  }
}

// MARK: - Resources

/// Describes a resource available from the server.
public struct Resource: Codable, Sendable, Equatable {
  // TODO: Remove once mock data is removed
  public init(uri: String, name: String? = nil, description: String? = nil, mimeType: String? = nil)
  {
    self.uri = uri
    self.name = name
    self.description = description
    self.mimeType = mimeType
  }

  /// The URI used to identify and retrieve this resource.
  public let uri: String

  /// A human-readable name for the resource.
  public let name: String?

  /// A brief description of the resource. This can help clients understand what the
  /// resource is and how it should be used.
  public let description: String?

  /// The MIME type of the resource, if applicable.
  public let mimeType: String?
}

/// Describes a resource template that the client can use to construct URIs for resources.
public struct ResourceTemplate: Codable, Sendable, Equatable {
  // TODO: Remove once mock data is removed
  public init(
    uriTemplate: String, name: String, description: String? = nil, mimeType: String? = nil,
    annotations: Annotations? = nil
  ) {
    self.uriTemplate = uriTemplate
    self.name = name
    self.description = description
    self.mimeType = mimeType
    self.annotations = annotations
  }

  /// A URI template according to RFC 6570 for constructing resource URIs.
  public let uriTemplate: String

  /// A human-readable name for the resource template.
  public let name: String

  /// A brief description of the resource template.
  public let description: String?

  /// The MIME type of resources that would be created from this template.
  public let mimeType: String?

  /// Optional annotations for the resource template.
  public let annotations: Annotations?
}

/// Sent from the client to request a list of resources the server has.
@JSONRPCRequest(method: "resources/list", responseType: ListResourcesResponse.self)
public struct ListResourcesRequest {
  public struct Params: Codable, Sendable {
    /// Optional pagination cursor.
    public let cursor: String?
  }
}

/// The server's response to `ListResourcesRequest`.
@JSONRPCResponse
public struct ListResourcesResponse {
  public struct Result: Codable, Sendable {
    /// The resources available from this server.
    public let resources: [Resource]

    /// Cursor used to fetch the next page of results.
    public let nextCursor: String?
  }
}

/// Sent from the client to read a specific resource from the server.
@JSONRPCRequest(method: "resources/read", responseType: ReadResourceResponse.self)
public struct ReadResourceRequest {
  public struct Params: Codable, Sendable {
    /// The URI of the resource to read.
    public let uri: String
  }
}

/// The server's response to `ReadResourceRequest`.
@JSONRPCResponse
public struct ReadResourceResponse {
  public struct Result: Codable, Sendable {
    /// The resource data.
    public let contents: [EmbeddedResource]
  }
}

/// Sent from the client to subscribe to changes to a resource.
@JSONRPCRequest(method: "resources/subscribe", responseType: EmptyResponse.self)
public struct SubscribeRequest {
  public struct Params: Codable, Sendable {
    /// The URI of the resource to subscribe to.
    public let uri: String
  }
}

/// Sent from the client to unsubscribe from changes to a resource.
@JSONRPCRequest(method: "resources/unsubscribe", responseType: EmptyResponse.self)
public struct UnsubscribeRequest {
  public struct Params: Codable, Sendable {
    /// The URI of the resource to unsubscribe from.
    public let uri: String
  }
}

/// An optional notification from the server to the client, informing it that
/// the list of resources it offers has changed.
@JSONRPCNotification(method: "notifications/resources/list_changed")
public struct ResourceListChangedNotification {
  public struct Params: Codable, Sendable {}
}

/// A notification from the server to the client, informing it that a resource
/// it has subscribed to has been updated.
@JSONRPCNotification(method: "notifications/resources/updated")
public struct ResourceUpdatedNotification {
  public struct Params: Codable, Sendable {
    /// The URI of the resource that has been updated.
    public let uri: String
  }
}

/// Sent from the client to request a list of resource templates the server has.
@JSONRPCRequest(
  method: "resources/templates/list", responseType: ListResourceTemplatesResponse.self)
public struct ListResourceTemplatesRequest {
  public struct Params: Codable, Sendable {
    /// Optional pagination cursor.
    public let cursor: String?
  }
}

/// The server's response to `ListResourceTemplatesRequest`.
@JSONRPCResponse
public struct ListResourceTemplatesResponse {
  public struct Result: Codable, Sendable {
    /// The resource templates available from this server.
    public let resourceTemplates: [ResourceTemplate]

    /// Cursor used to fetch the next page of results.
    public let nextCursor: String?
  }
}

// MARK: - Prompts

/// Definition for a prompt template that the client can use.
public struct Prompt: Codable, Sendable, Equatable {
  // TODO: remove once mock data is removed
  public init(name: String, description: String? = nil, arguments: [PromptArgument]? = nil) {
    self.name = name
    self.description = description
    self.arguments = arguments
  }

  /// The name of the prompt template.
  public let name: String

  /// A human-readable description of the prompt.
  public let description: String?

  /// The arguments that can be passed to this prompt template.
  public let arguments: [PromptArgument]?
}

/// Describes an argument that can be passed to a prompt.
public struct PromptArgument: Codable, Sendable, Equatable {
  // TODO: remove once mock data is removed
  public init(name: String, description: String? = nil, required: Bool? = nil) {
    self.name = name
    self.description = description
    self.required = required
  }

  /// The name of the argument.
  public let name: String

  /// A human-readable description of the argument.
  public let description: String?

  /// Whether this argument is required.
  public let required: Bool?
}

/// Sent from the client to request a list of prompt templates the server has.
@JSONRPCRequest(method: "prompts/list", responseType: ListPromptsResponse.self)
public struct ListPromptsRequest {
  public struct Params: Codable, Sendable {
    /// Optional pagination cursor.
    public let cursor: String?
  }
}

/// The server's response to `ListPromptsRequest`.
@JSONRPCResponse
public struct ListPromptsResponse {
  public struct Result: Codable, Sendable {
    /// The prompt templates available from this server.
    public let prompts: [Prompt]

    /// Cursor used to fetch the next page of results.
    public let nextCursor: String?
  }
}

/// A message in a prompt template, containing only role and content.
public struct PromptMessage: Codable, Sendable {
  // TODO: remove once mock data is removed
  public init(role: Role, content: Content) {
    self.role = role
    self.content = content
  }

  /// The role of the message sender (user or assistant).
  public let role: Role

  /// The content of the message.
  public let content: Content
}

/// Sent from the client to get a specific prompt template from the server.
@JSONRPCRequest(method: "prompts/get", responseType: GetPromptResponse.self)
public struct GetPromptRequest {
  public struct Params: Codable, Sendable {
    /// The name of the prompt template to get.
    public let name: String

    /// Optional arguments to customize the prompt.
    public let arguments: [String: String]?
  }
}

/// The server's response to `GetPromptRequest`.
@JSONRPCResponse
public struct GetPromptResponse {
  public struct Result: Codable, Sendable {
    // TODO: remove once mock data is removed
    public init(description: String? = nil, messages: [PromptMessage]) {
      self.description = description
      self.messages = messages
    }

    /// A human-readable description of the prompt.
    public let description: String?

    /// The list of messages in the prompt.
    public let messages: [PromptMessage]
  }
}

/// An optional notification from the server to the client, informing it that
/// the list of prompt templates it offers has changed.
@JSONRPCNotification(method: "notifications/prompts/list_changed")
public struct PromptListChangedNotification {
  public struct Params: Codable, Sendable {}
}

// MARK: - Completion

/// A reference to a prompt or resource.
public enum Reference: Codable, Sendable {
  /// A reference to a prompt or prompt template definition.
  case prompt(name: String)
  /// A reference to a resource or resource template definition.
  case resource(uri: String)

  private enum CodingKeys: String, CodingKey {
    case type
    case name
    case uri
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .prompt(let name):
      try container.encode("ref/prompt", forKey: .type)
      try container.encode(name, forKey: .name)
    case .resource(let uri):
      try container.encode("ref/resource", forKey: .type)
      try container.encode(uri, forKey: .uri)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "ref/prompt":
      let name = try container.decode(String.self, forKey: .name)
      self = .prompt(name: name)
    case "ref/resource":
      let uri = try container.decode(String.self, forKey: .uri)
      self = .resource(uri: uri)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Invalid reference type: \(type)"
      )
    }
  }
}

/// A request from the client to the server, to ask for completion options.
@JSONRPCRequest(method: "completion/complete", responseType: CompleteResponse.self)
public struct CompleteRequest {
  public struct Argument: Codable, Sendable {
    /// The name of the argument.
    public let name: String

    /// The value of the argument to use for completion matching.
    public let value: String
  }

  public struct Params: Codable, Sendable {
    /// A reference to a prompt or resource.
    public let ref: Reference

    /// The name and value of the argument.
    public let argument: Argument
  }
}

/// The server's response to `CompleteRequest`
@JSONRPCResponse
public struct CompleteResponse {
  public struct Completion: Codable, Sendable {
    /// An array of completion values. Must not exceed 100 items.
    public let values: [String]

    /// The total number of completion options available. This can exceed
    /// the number of values actually sent in the response.
    public let total: Int?

    /// Indicates whether there are additional completion options beyond
    /// those provided in the current response, even if the exact total is unknown.
    public let hasMore: Bool?
  }

  public struct Result: Codable, Sendable {
    public let completion: Completion
  }
}

// MARK: - Sampling

/// A message for sampling requests, containing only role and content.
public struct SamplingMessage: Codable, Sendable {
  /// The role of the message sender (user or assistant).
  public let role: Role

  /// The content of the message.
  public let content: Content
}

/// Preferences for model selection in sampling requests.
public struct ModelPreferences: Codable, Sendable {
  /// Cost priority for model selection.
  public let costPriority: Double?

  /// Speed priority for model selection.
  public let speedPriority: Double?

  /// Intelligence priority for model selection.
  public let intelligencePriority: Double?
}

/// Context inclusion options for sampling requests.
public enum IncludeContext: String, Codable, Sendable {
  case none = "none"
  case thisServer = "thisServer"
  case allServers = "allServers"
}

/// A message in a conversation between a user and an assistant.
public struct Message: Codable, Sendable {
  /// The role of the message sender (user or assistant).
  public let role: Role

  /// The content of the message.
  public let content: Content

  /// A unique identifier for this message.
  public let id: String?

  /// The name of the author of this message.
  public let name: String?
}

/// Options for controlling the behavior of sampling.
public struct SamplingOptions: Codable, Sendable {
  /// The temperature to use for sampling.
  /// Higher values (e.g., 0.8) make the output more random,
  /// while lower values (e.g., 0.2) make it more deterministic.
  public let temperature: Double?

  /// A non-negative integer that defines how many most-likely candidates
  /// are considered at each step. A higher value means more possibilities
  /// are considered, increasing diversity but decreasing efficiency.
  public let topK: Int?

  /// A float between 0 and 1. Only the most likely candidates with
  /// probabilities that add up to topP are considered. Like topK,
  /// it limits the number of candidates considered at each step.
  public let topP: Double?

  /// A float between 0 and 1 that penalizes tokens based on their
  /// frequency in the training data. Higher values discourage common tokens.
  public let frequencyPenalty: Double?

  /// A float between 0 and 1 that penalizes tokens that have already appeared
  /// in the generated text. Higher values discourage repetition.
  public let presencePenalty: Double?

  /// The maximum number of tokens to generate.
  public let maxTokens: Int?
}

/// A request from the server to the client, to create a message from the model.
@JSONRPCRequest(method: "sampling/createMessage", responseType: CreateMessageResponse.self)
public struct CreateMessageRequest {
  public struct Params: Codable, Sendable {
    /// The conversation history.
    public let messages: [SamplingMessage]

    /// Preferences for model selection.
    public let modelPreferences: ModelPreferences?

    /// System prompt to include in the conversation.
    public let systemPrompt: String?

    /// Whether to include context from the server.
    public let includeContext: IncludeContext?

    /// Temperature for sampling (0.0 to 1.0).
    public let temperature: Double?

    /// Maximum number of tokens to generate.
    public let maxTokens: Int

    /// Stop sequences for sampling.
    public let stopSequences: [String]?

    /// Additional metadata for the request.
    public let metadata: JSONValue?
  }
}

/// Stop reasons for sampling.
public enum StopReason: String, Codable, Sendable {
  case endTurn = "endTurn"
  case stopSequence = "stopSequence"
  case maxTokens = "maxTokens"
}

/// The client's response to `CreateMessageRequest`.
@JSONRPCResponse
public struct CreateMessageResponse {
  public struct Result: Codable, Sendable {
    /// The role of the message sender.
    public let role: Role

    /// The content of the message.
    public let content: Content

    /// The model that generated this message.
    public let model: String

    /// The reason sampling stopped.
    public let stopReason: String?
  }
}

/// A simple ping request to check if the server is still responsive.
@JSONRPCRequest(method: "ping", responseType: PingResponse.self)
public struct PingRequest {
  public struct Params: Codable, Sendable {}
}

/// The server's response to `PingRequest`.
@JSONRPCResponse
public struct PingResponse {
  public struct Result: Codable, Sendable {}
}

// MARK: - Tools

/// Additional properties describing a `Tool` to clients.
///
/// NOTE: all properties in `ToolAnnotations are` **hints**. They are not guaranteed
/// to provide a faithful description of tool behavior (including descriptive
/// properties like `title`).
///
/// Clients should never make tool use decisions based on `ToolAnnotations` received
/// from untrusted servers.
public struct ToolAnnotations: Codable, Sendable, Equatable {
  public init(
    title: String? = nil, readOnlyHint: Bool? = nil, destructiveHint: Bool? = nil,
    idempotentHint: Bool? = nil, openWorldHint: Bool? = nil
  ) {
    self.title = title
    self.readOnlyHint = readOnlyHint
    self.destructiveHint = destructiveHint
    self.idempotentHint = idempotentHint
    self.openWorldHint = openWorldHint
  }

  /// A human-readable title for the tool.
  public let title: String?

  /// If true, the tool does not modify its environment.
  ///
  /// Default: false
  public let readOnlyHint: Bool?

  /// If true, the tool may perform destructive updates to its environment.
  /// If false, the tool performs only additive updates.
  ///
  /// (This property is meaningful only when `readOnlyHint == false`)
  ///
  /// Default: true
  public let destructiveHint: Bool?

  /// If true, calling the tool repeatedly with the same arguments will have no
  /// additional effect on its environment.
  ///
  /// (This property is meaningful only when `readOnlyHint == false`)
  ///
  /// Default: false
  public let idempotentHint: Bool?

  /// If true, this tool may interact with an "open world" of external entities.
  /// If false, the tool's domain of interaction is closed. For example, the world
  /// of a web search tool is open, whereas that of a memory tool is not.
  ///
  /// Default: true
  public let openWorldHint: Bool?
}

/// Definition for a tool the client can call.
public struct Tool: Codable, Sendable, Equatable {
  // TODO: remove once mock data is removed
  public init(
    name: String, description: String? = nil, inputSchema: Tool.InputSchema,
    annotations: ToolAnnotations? = nil
  ) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
    self.annotations = annotations
  }

  /// A JSON Schema object defining the expected parameters for the tool.
  public struct InputSchema: Codable, Sendable, Equatable {
    // TODO: remove once mock data is removed
    public init(type: String, properties: [String: JSONValue]? = nil, required: [String]? = nil) {
      self.type = type
      self.properties = properties
      self.required = required
    }

    public let type: String  // object
    public let properties: [String: JSONValue]?
    public let required: [String]?
  }

  /// The name of the tool.
  public let name: String

  /// A human-readable description of the tool.
  ///
  ///This can be used by clients to improve the LLM's understanding of available
  ///tools. It can be thought of like a "hint" to the model.
  public let description: String?

  /// A JSON Schema object defining the expected parameters for the tool.
  public let inputSchema: InputSchema

  /// Optional additional tool information.
  public let annotations: ToolAnnotations?
}

///Sent from the client to request a list of tools the server has.
@JSONRPCRequest(method: "tools/list", responseType: ListToolsResponse.self)
public struct ListToolsRequest {
  public struct Params: Codable, Sendable {
    /// Optional pagination cursor.
    public let cursor: String?
  }
}

/// The server's response to `ListToolsRequest`
@JSONRPCResponse
public struct ListToolsResponse {
  public struct Result: Codable, Sendable {
    public let tools: [Tool]

    /// Cursor used to fetch the next page of results.
    public let nextCursor: String?
  }
}

/// Used by the client to invoke a tool provided by the server.
@JSONRPCRequest(method: "tools/call", responseType: CallToolResponse.self)
public struct CallToolRequest {
  public struct Params: Codable, Sendable {
    /// The name of the tool to call.
    public let name: String

    /// The arguments to call the tool with.
    public let arguments: [String: JSONValue]?
  }
}

/// The server's response to `CallToolRequest`
@JSONRPCResponse
public struct CallToolResponse {
  // TODO: remove once mock data is removed
  public init(jsonrpc: String, result: CallToolResponse.Result, id: JSONRPCRequestID) {
    self.jsonrpc = jsonrpc
    self.result = result
    self.id = id
  }

  public struct Result: Codable, Sendable {
    // TODO: Remove once mock data is removed
    public init(content: [Content], isError: Bool? = nil) {
      self.content = content
      self.isError = isError
    }

    public let content: [Content]
    /// Whether the tool call ended in an error.
    ///
    /// If not set, this is assumed to be false (the call was successful).
    public let isError: Bool?
  }
}

/// An optional notification from the server to the client, informing it that the
/// list of tools it offers has changed. This may be issued by servers without
/// any previous subscription from the client.
@JSONRPCNotification(method: "notifications/tools/list_changed")
public struct ToolListChangedNotification {
  public struct Params: Codable, Sendable {}
}
