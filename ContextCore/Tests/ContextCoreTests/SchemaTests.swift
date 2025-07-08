// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

extension Encodable {
  func encodeToJSON() throws -> Data {
    try JSONEncoder().encode(self)
  }

  func encodeToJSONString() throws -> String {
    let data = try encodeToJSON()
    guard let string = String(data: data, encoding: .utf8) else {
      throw NSError(
        domain: "SchemaTests", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to encode to JSON string"])
    }
    return string
  }
}

@Suite(.timeLimit(.minutes(1))) struct SchemaTests {
  // MARK: - Basic Types Tests

  @Test func testRoleEncoding() async throws {
    let userRole = Role.user
    let assistantRole = Role.assistant

    #expect(try userRole.encodeToJSONString() == "\"user\"")
    #expect(try assistantRole.encodeToJSONString() == "\"assistant\"")

    let decodedUserRole = try JSONDecoder().decode(Role.self, from: "\"user\"".data(using: .utf8)!)
    let decodedAssistantRole = try JSONDecoder().decode(
      Role.self, from: "\"assistant\"".data(using: .utf8)!)

    #expect(decodedUserRole == userRole)
    #expect(decodedAssistantRole == assistantRole)
  }

  @Test func testAnnotationsEncodingDecoding() async throws {
    let annotations = Annotations(audience: [.user, .assistant], priority: 0.8)
    let data = try annotations.encodeToJSON()
    let decoded = try JSONDecoder().decode(Annotations.self, from: data)

    #expect(decoded.audience?.count == 2)
    #expect(decoded.audience?[0] == .user)
    #expect(decoded.audience?[1] == .assistant)
    #expect(decoded.priority == 0.8)
  }

  @Test func testContentTextEncodingDecoding() async throws {
    let content = Content.text("Hello, world!", annotations: nil)
    let data = try content.encodeToJSON()
    let decoded = try JSONDecoder().decode(Content.self, from: data)

    if case let .text(text, annotations) = decoded {
      #expect(text == "Hello, world!")
      #expect(annotations == nil)
    } else {
      Issue.record("Decoded content is not text")
    }
  }

  @Test func testContentImageEncodingDecoding() async throws {
    let imageData = "test-image-data".data(using: .utf8)!
    let content = Content.image(data: imageData, mimeType: "image/png", annotations: nil)
    let data = try content.encodeToJSON()
    let decoded = try JSONDecoder().decode(Content.self, from: data)

    if case let .image(data, mimeType, annotations) = decoded {
      #expect(data == imageData)
      #expect(mimeType == "image/png")
      #expect(annotations == nil)
    } else {
      Issue.record("Decoded content is not image")
    }
  }

  @Test func testContentAudioEncodingDecoding() async throws {
    let audioData = "test-audio-data".data(using: .utf8)!
    let content = Content.audio(data: audioData, mimeType: "audio/mp3", annotations: nil)
    let data = try content.encodeToJSON()
    let decoded = try JSONDecoder().decode(Content.self, from: data)

    if case let .audio(data, mimeType, annotations) = decoded {
      #expect(data == audioData)
      #expect(mimeType == "audio/mp3")
      #expect(annotations == nil)
    } else {
      Issue.record("Decoded content is not audio")
    }
  }

  @Test func testContentWithAnnotations() async throws {
    let annotations = Annotations(audience: [.user], priority: 0.5)
    let content = Content.text("Hello with annotation", annotations: annotations)
    let data = try content.encodeToJSON()
    let decoded = try JSONDecoder().decode(Content.self, from: data)

    if case let .text(text, decodedAnnotations) = decoded {
      #expect(text == "Hello with annotation")
      #expect(decodedAnnotations?.audience?.count == 1)
      #expect(decodedAnnotations?.audience?[0] == .user)
      #expect(decodedAnnotations?.priority == 0.5)
    } else {
      Issue.record("Decoded content is not text")
    }
  }

  // MARK: - Reference Tests

  @Test func testReferencePromptEncodingDecoding() async throws {
    let reference = Reference.prompt(name: "my-prompt")
    let data = try reference.encodeToJSON()
    let decoded = try JSONDecoder().decode(Reference.self, from: data)

    if case let .prompt(name) = decoded {
      #expect(name == "my-prompt")
    } else {
      Issue.record("Decoded reference is not prompt")
    }
  }

  @Test func testReferenceResourceEncodingDecoding() async throws {
    let reference = Reference.resource(uri: "file:///example.txt")
    let data = try reference.encodeToJSON()
    let decoded = try JSONDecoder().decode(Reference.self, from: data)

    if case let .resource(uri) = decoded {
      #expect(uri == "file:///example.txt")
    } else {
      Issue.record("Decoded reference is not resource")
    }
  }

  // MARK: - Tool Tests

  @Test func testToolEncodingDecoding() async throws {
    let inputSchema = Tool.InputSchema(
      type: "object",
      properties: [
        "name": JSONValue.object(["type": "string"]),
        "age": JSONValue.object(["type": "integer"]),
      ],
      required: ["name"]
    )

    let annotations = ToolAnnotations(
      title: "Test Tool",
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )

    let tool = Tool(
      name: "test-tool",
      description: "A test tool for testing",
      inputSchema: inputSchema,
      annotations: annotations
    )

    let data = try tool.encodeToJSON()
    let decoded = try JSONDecoder().decode(Tool.self, from: data)

    #expect(decoded.name == "test-tool")
    #expect(decoded.description == "A test tool for testing")
    #expect(decoded.inputSchema.type == "object")
    #expect(decoded.inputSchema.required?.count == 1)
    #expect(decoded.inputSchema.required?[0] == "name")
    #expect(decoded.annotations?.title == "Test Tool")
    #expect(decoded.annotations?.readOnlyHint == true)
    #expect(decoded.annotations?.destructiveHint == false)
    #expect(decoded.annotations?.idempotentHint == true)
    #expect(decoded.annotations?.openWorldHint == false)
  }

  // MARK: - Message Tests

  @Test func testMessageEncodingDecoding() async throws {
    let message = Message(
      role: .assistant,
      content: .text("Hello, I'm an assistant", annotations: nil),
      id: "msg-123",
      name: "AI Assistant"
    )

    let data = try message.encodeToJSON()
    let decoded = try JSONDecoder().decode(Message.self, from: data)

    #expect(decoded.role == .assistant)
    #expect(decoded.id == "msg-123")
    #expect(decoded.name == "AI Assistant")

    if case let .text(text, _) = decoded.content {
      #expect(text == "Hello, I'm an assistant")
    } else {
      Issue.record("Message content type is not text")
    }
  }

  // MARK: - Request/Response Tests

  @Test func testInitializeRequestEncodingDecoding() async throws {
    let request = InitializeRequest(
      id: .string("req-1"),
      protocolVersion: "2025-03-26",
      capabilities: ClientCapabilities(),
      clientInfo: Implementation(name: "Test Client", version: "1.0.0")
    )

    let data = try request.encodeToJSON()
    let decoded = try JSONDecoder().decode(InitializeRequest.self, from: data)

    #expect(decoded.jsonrpc == "2.0")
    #expect(decoded.method == "initialize")
    #expect(decoded.params?.protocolVersion == "2025-03-26")
    #expect(decoded.params?.clientInfo.name == "Test Client")
    #expect(decoded.params?.clientInfo.version == "1.0.0")

    if case let .string(idValue) = decoded.id {
      #expect(idValue == "req-1")
    } else {
      Issue.record("Request ID is not a string")
    }
  }

  @Test func testInitializeResponseEncodingDecoding() async throws {
    let response = InitializeResponse(
      id: .string("req-1"),
      protocolVersion: "2025-03-26",
      capabilities: ServerCapabilities(),
      serverInfo: Implementation(name: "Test Server", version: "1.0.0")
    )

    let data = try response.encodeToJSON()
    let decoded = try JSONDecoder().decode(InitializeResponse.self, from: data)

    #expect(decoded.jsonrpc == "2.0")
    #expect(decoded.result.protocolVersion == "2025-03-26")
    #expect(decoded.result.serverInfo.name == "Test Server")
    #expect(decoded.result.serverInfo.version == "1.0.0")

    if case let .string(idValue) = decoded.id {
      #expect(idValue == "req-1")
    } else {
      Issue.record("Response ID is not a string")
    }
  }

  @Test func testResourceRequestResponseEncodingDecoding() async throws {
    // ListResourcesRequest
    let listRequest = ListResourcesRequest(id: .number(1), cursor: nil)
    let listRequestData = try listRequest.encodeToJSON()
    let decodedListRequest = try JSONDecoder().decode(
      ListResourcesRequest.self, from: listRequestData)

    #expect(decodedListRequest.method == "resources/list")
    #expect(decodedListRequest.params?.cursor == nil)

    // ReadResourceRequest
    let readRequest = ReadResourceRequest(id: .number(2), uri: "file:///example.txt")
    let readRequestData = try readRequest.encodeToJSON()
    let decodedReadRequest = try JSONDecoder().decode(
      ReadResourceRequest.self, from: readRequestData)

    #expect(decodedReadRequest.method == "resources/read")
    #expect(decodedReadRequest.params?.uri == "file:///example.txt")

    // ReadResourceResponse
    let contents: [EmbeddedResource] = [
      .text(
        TextResourceContents(
          uri: "file:///example.txt", mimeType: "text/plain", text: "File content"))
    ]
    let readResponse = ReadResourceResponse(
      id: .number(2),
      contents: contents
    )

    let readResponseData = try readResponse.encodeToJSON()
    let decodedReadResponse = try JSONDecoder().decode(
      ReadResourceResponse.self, from: readResponseData)

    #expect(decodedReadResponse.jsonrpc == "2.0")
    #expect(decodedReadResponse.result.contents.count == 1)

    if case let .text(contents) = decodedReadResponse.result.contents[0] {
      #expect(contents.text == "File content")
    } else {
      Issue.record("Response content type is not text")
    }
  }

  @Test func testNotificationsEncodingDecoding() async throws {
    // CancelledNotification
    let cancelledNotification = CancelledNotification(requestId: .number(123), reason: nil)
    let cancelledData = try cancelledNotification.encodeToJSON()
    let decodedCancelled = try JSONDecoder().decode(CancelledNotification.self, from: cancelledData)

    #expect(decodedCancelled.method == "notifications/cancelled")
    #expect(decodedCancelled.params?.requestId == .number(123))

    // ProgressNotification
    let progressNotification = ProgressNotification(
      id: .string("req-456"),
      progress: 0.75,
      message: "Loading resources..."
    )

    let progressData = try progressNotification.encodeToJSON()
    let decodedProgress = try JSONDecoder().decode(ProgressNotification.self, from: progressData)

    #expect(decodedProgress.method == "notifications/progress")
    #expect(decodedProgress.params?.id == .string("req-456"))
    #expect(decodedProgress.params?.progress == 0.75)
    #expect(decodedProgress.params?.message == "Loading resources...")
  }

  @Test func testLoggingEncodingDecoding() async throws {
    // SetLevelRequest
    let setLevelRequest = SetLevelRequest(id: .number(1), level: .debug)
    let setLevelData = try setLevelRequest.encodeToJSON()
    let decodedSetLevel = try JSONDecoder().decode(SetLevelRequest.self, from: setLevelData)

    #expect(decodedSetLevel.method == "logging/setLevel")
    #expect(decodedSetLevel.params?.level == .debug)

    // LoggingMessageNotification
    let loggingNotification = LoggingMessageNotification(
      level: .info,
      logger: "AppLogger",
      data: .string("This is a log message")
    )

    let loggingData = try loggingNotification.encodeToJSON()
    let decodedLogging = try JSONDecoder().decode(
      LoggingMessageNotification.self, from: loggingData)

    #expect(decodedLogging.method == "notifications/message")
    #expect(decodedLogging.params?.level == .info)
    #expect(decodedLogging.params?.logger == "AppLogger")

    if case let .string(message) = decodedLogging.params?.data {
      #expect(message == "This is a log message")
    } else {
      Issue.record("Log data is not a string")
    }
  }

  @Test
  func testToolRequestResponseEncodingDecoding() async throws {
    // CallToolRequest
    let arguments: [String: JSONValue] = [
      "query": "How to make pasta",
      "limit": 5,
    ]

    let callRequest = CallToolRequest(id: .number(42), name: "search", arguments: arguments)
    let callRequestData = try callRequest.encodeToJSON()
    let decodedCallRequest = try JSONDecoder().decode(CallToolRequest.self, from: callRequestData)

    #expect(decodedCallRequest.method == "tools/call")
    #expect(decodedCallRequest.params?.name == "search")
    #expect(decodedCallRequest.params?.arguments?["query"] == .string("How to make pasta"))
    #expect(decodedCallRequest.params?.arguments?["limit"] == .integer(5))

    // CallToolResponse
    let content: [Content] = [
      .text("Here are pasta recipes:", annotations: nil),
      .text("1. Spaghetti Carbonara", annotations: nil),
    ]

    let callResponse = CallToolResponse(
      id: .number(42),
      content: content,
      isError: false
    )

    let callResponseData = try callResponse.encodeToJSON()
    let decodedCallResponse = try JSONDecoder().decode(
      CallToolResponse.self, from: callResponseData)

    #expect(decodedCallResponse.result.content.count == 2)
    #expect(decodedCallResponse.result.isError == false)

    if case let .text(text1, _) = decodedCallResponse.result.content[0],
      case let .text(text2, _) = decodedCallResponse.result.content[1]
    {
      #expect(text1 == "Here are pasta recipes:")
      #expect(text2 == "1. Spaghetti Carbonara")
    } else {
      Issue.record("Response content types are not text")
    }
  }

  @Test func testSamplingEncodingDecoding() async throws {
    // Test SamplingMessage
    let samplingMessage = SamplingMessage(
      role: .user,
      content: .text("What's the weather like?", annotations: nil)
    )

    let messageData = try samplingMessage.encodeToJSON()
    let decodedMessage = try JSONDecoder().decode(SamplingMessage.self, from: messageData)

    #expect(decodedMessage.role == .user)
    if case let .text(text, _) = decodedMessage.content {
      #expect(text == "What's the weather like?")
    } else {
      Issue.record("SamplingMessage content type is not text")
    }

    // Test ModelPreferences
    let modelPreferences = ModelPreferences(
      costPriority: 0.3,
      speedPriority: 0.7,
      intelligencePriority: 0.9
    )

    let preferencesData = try modelPreferences.encodeToJSON()
    let decodedPreferences = try JSONDecoder().decode(ModelPreferences.self, from: preferencesData)

    #expect(decodedPreferences.costPriority == 0.3)
    #expect(decodedPreferences.speedPriority == 0.7)
    #expect(decodedPreferences.intelligencePriority == 0.9)

    // Test SamplingOptions
    let options = SamplingOptions(
      temperature: 0.7,
      topK: 40,
      topP: 0.9,
      frequencyPenalty: 0.5,
      presencePenalty: 0.5,
      maxTokens: 1000
    )

    let optionsData = try options.encodeToJSON()
    let decodedOptions = try JSONDecoder().decode(SamplingOptions.self, from: optionsData)

    #expect(decodedOptions.temperature == 0.7)
    #expect(decodedOptions.topK == 40)
    #expect(decodedOptions.topP == 0.9)
    #expect(decodedOptions.frequencyPenalty == 0.5)
    #expect(decodedOptions.presencePenalty == 0.5)
    #expect(decodedOptions.maxTokens == 1000)

    // Test CreateMessageRequest
    let messages = [samplingMessage]

    let createRequest = CreateMessageRequest(
      id: .string("req-123"),
      messages: messages,
      modelPreferences: modelPreferences,
      systemPrompt: "You are a helpful assistant.",
      includeContext: .thisServer,
      temperature: 0.7,
      maxTokens: 1000,
      stopSequences: ["END"],
      metadata: .object(["source": "test"])
    )

    let createRequestData = try createRequest.encodeToJSON()
    let decodedCreateRequest = try JSONDecoder().decode(
      CreateMessageRequest.self, from: createRequestData)

    #expect(decodedCreateRequest.method == "sampling/createMessage")
    #expect(decodedCreateRequest.params?.messages.count == 1)
    #expect(decodedCreateRequest.params?.messages[0].role == .user)
    #expect(decodedCreateRequest.params?.temperature == 0.7)
    #expect(decodedCreateRequest.params?.maxTokens == 1000)
    #expect(decodedCreateRequest.params?.systemPrompt == "You are a helpful assistant.")
    #expect(decodedCreateRequest.params?.includeContext == .thisServer)
    #expect(decodedCreateRequest.params?.stopSequences?.count == 1)
    #expect(decodedCreateRequest.params?.stopSequences?[0] == "END")
    #expect(decodedCreateRequest.params?.modelPreferences?.costPriority == 0.3)

    // Test CreateMessageResponse
    let createResponse = CreateMessageResponse(
      id: .string("req-123"),
      role: .assistant,
      content: .text("It's sunny today!", annotations: nil),
      model: "gpt-4",
      stopReason: "endTurn"
    )

    let createResponseData = try createResponse.encodeToJSON()
    let decodedCreateResponse = try JSONDecoder().decode(
      CreateMessageResponse.self, from: createResponseData)

    #expect(decodedCreateResponse.result.role == .assistant)
    #expect(decodedCreateResponse.result.model == "gpt-4")
    #expect(decodedCreateResponse.result.stopReason == "endTurn")

    if case let .text(text, _) = decodedCreateResponse.result.content {
      #expect(text == "It's sunny today!")
    } else {
      Issue.record("Response content type is not text")
    }
  }
}
