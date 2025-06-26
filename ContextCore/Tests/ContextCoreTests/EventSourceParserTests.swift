// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Testing

@testable import ContextCore

@Suite(.timeLimit(.minutes(1))) struct EventSourceParserTests {
  @Test func testBasicEvent() async throws {
    let input = "data: hello world\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].eventType == "message")
    #expect(events[0].data == "hello world")
    #expect(events[0].id == nil)
    #expect(events[0].retryMs == nil)
  }

  @Test func testEventWithType() async throws {
    let input = "event: update\ndata: stock price changed\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].eventType == "update")
    #expect(events[0].data == "stock price changed")
  }

  @Test func testEventWithId() async throws {
    let input = "id: 1\ndata: with an id\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "with an id")
    #expect(events[0].id == "1")
  }

  @Test func testEventWithRetry() async throws {
    let parser = EventSourceParser()
    let input = "retry: 10000\ndata: retry in 10s\n\n"
    let events = try await parseEvents(from: input, using: parser)

    #expect(events.count == 1)
    #expect(events[0].data == "retry in 10s")
    #expect(events[0].retryMs == 10000)
  }

  @Test func testInvalidRetry() async throws {
    let parser = EventSourceParser()
    let input = "retry: not-a-number\ndata: invalid retry\n\n"
    let events = try await parseEvents(from: input, using: parser)

    #expect(events.count == 1)
    #expect(events[0].data == "invalid retry")
    #expect(events[0].retryMs == nil)
  }

  // MARK: - Multiple Events Tests

  @Test func testMultipleEvents() async throws {
    let input = "data: first event\n\ndata: second event\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 2)
    #expect(events[0].data == "first event")
    #expect(events[1].data == "second event")
  }

  @Test func testEventIdPersistence() async throws {
    let parser = EventSourceParser()
    let input = "id: 1\ndata: first event\n\ndata: second event\n\n"
    let events = try await parseEvents(from: input, using: parser)

    #expect(events.count == 2)
    #expect(events[0].id == "1")
    // The second event should inherit the ID from the first event
    #expect(events[1].id == "1")
    #expect(await parser.lastEventId == "1")
  }

  @Test func testEventIdUpdate() async throws {
    let parser = EventSourceParser()
    let input = "id: 1\ndata: first event\n\nid: 2\ndata: second event\n\n"
    let events = try await parseEvents(from: input, using: parser)

    #expect(events.count == 2)
    #expect(events[0].id == "1")
    #expect(events[1].id == "2")
    #expect(await parser.lastEventId == "2")
  }

  @Test func testMultilineData() async throws {
    let input = "data: first line\ndata: second line\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "first line\nsecond line")
  }

  @Test func testEmptyData() async throws {
    let input = "data:\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "")
  }

  @Test func testComments() async throws {
    let input = ": this is a comment\ndata: actual data\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "actual data")
  }

  @Test func testFieldsWithoutColon() async throws {
    let input = "event\ndata: test\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].eventType == "")  // Event type should be empty string, not "message"
    #expect(events[0].data == "test")
  }

  @Test func testSpaceAfterColon() async throws {
    let input = "data: with space\ndata:without space\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "with space\nwithout space")
  }

  @Test func testIgnoreIdWithNullByte() async throws {
    let input = "id: 1\u{0000}2\ndata: test\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].id == nil)  // ID should be ignored due to null byte
  }

  // MARK: - Line Ending Tests

  @Test func testCRLFLineEndings() async throws {
    let input = "data: line 1\r\ndata: line 2\r\n\r\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "line 1\nline 2")
  }

  @Test func testCRLineEndings() async throws {
    let input = "data: line 1\rdata: line 2\r\r"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "line 1\nline 2")
  }

  @Test func testMixedLineEndings() async throws {
    let input = "data: line 1\ndata: line 2\r\rdata: line 3\r\n\r\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 2)
    #expect(events[0].data == "line 1\nline 2")
    #expect(events[1].data == "line 3")
  }

  @Test func testReset() async throws {
    let parser = EventSourceParser()

    // First parse an event with an ID
    let input1 = "id: 1\ndata: first event\n\n"
    var events = try await parseEvents(from: input1, using: parser)

    #expect(events.count == 1)
    #expect(events[0].id == "1")
    #expect(await parser.lastEventId == "1")

    // Now reset and parse another event
    await parser.reset()

    let input2 = "data: after reset\n\n"
    events = try await parseEvents(from: input2, using: parser)

    #expect(events.count == 1)
    #expect(events[0].data == "after reset")
    // ID should persist after reset
    #expect(events[0].id == "1")
    #expect(await parser.lastEventId == "1")
  }

  // MARK: - Edge Cases

  @Test func testEmptyInput() async throws {
    let input = ""
    let events = try await parseEvents(from: input)

    #expect(events.count == 0)
  }

  @Test func testOnlyComments() async throws {
    let input = ": comment 1\n: comment 2\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 0)
  }

  @Test func testUnknownFields() async throws {
    let input = "unknown: field\ndata: test\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "test")
  }

  @Test func testMultilineDataWithMixedContent() async throws {
    let input = "data: first line\nevent: update\ndata: second line\nid: 123\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].eventType == "update")
    #expect(events[0].data == "first line\nsecond line")
    #expect(events[0].id == "123")
  }

  @Test func testConsecutiveEmptyLines() async throws {
    let input = "data: line\n\n\n\ndata: after empty lines\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 2)
    #expect(events[0].data == "line")
    #expect(events[1].data == "after empty lines")
  }

  @Test func testEventWithInvalidUTF8() async throws {
    // Create a byte sequence with invalid UTF-8
    let validBytes = byteSequence(from: "data: ")
    var invalidBytes = validBytes
    // Add some invalid UTF-8 bytes
    invalidBytes.append(contentsOf: [0xFF, 0xFE, 0xFD])
    invalidBytes.append(contentsOf: byteSequence(from: "\n\n"))

    let byteStream = AsyncStream<UInt8> { continuation in
      for byte in invalidBytes {
        continuation.yield(byte)
      }
      continuation.finish()
    }

    let parser = EventSourceParser()
    var events: [ServerSentEvent] = []
    events = try await withTimeout(
      timeoutMessage: "Timeout waiting for parser to process invalid UTF-8",
      defaultValue: [ServerSentEvent]()
    ) {
      var collectedEvents: [ServerSentEvent] = []
      for try await event in await parser.parse(byteStream: byteStream) {
        collectedEvents.append(event)
      }
      return collectedEvents
    }

    // Expect no events since the line couldn't be decoded as UTF-8
    #expect(events.count == 0)
  }

  @Test func testMultipleRetriesKeepsLast() async throws {
    let parser = EventSourceParser()
    let input = "retry: 5000\nretry: 8000\ndata: test\n\n"
    let events = try await parseEvents(from: input, using: parser)

    #expect(events.count == 1)
    #expect(events[0].retryMs == 8000)
  }

  @Test func testNonASCIICharacters() async throws {
    let input = "data: 你好世界\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "你好世界")
  }

  @Test func testTrailingLFRemoval() async throws {
    // Test with a trailing LF in the data field
    let input = "data: line with trailing LF\n\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "line with trailing LF")

    // Test with multiple data fields where last one has trailing LF
    let input2 = "data: first line\ndata: second line\n\n\n"
    let events2 = try await parseEvents(from: input2)

    #expect(events2.count == 1)
    #expect(events2[0].data == "first line\nsecond line")
  }

  // MARK: - Error Handling and Edge Cases

  @Test func testStreamErrorPropagation() async throws {
    // Create a stream that throws an error
    struct TestError: Error {}

    let byteStream = AsyncThrowingStream<UInt8, Error> { continuation in
      // First yield some valid data
      for byte in "data: test\n\n".utf8 {
        continuation.yield(byte)
      }
      // Then throw an error
      continuation.finish(throwing: TestError())
    }

    let parser = EventSourceParser()

    // We should get the first event but then the stream should throw
    var events: [ServerSentEvent] = []
    var caughtError = false

    do {
      // Don't use timeout here since we expect this to throw TestError quickly
      for try await event in await parser.parse(byteStream: byteStream) {
        events.append(event)
      }
    } catch is TestError {
      caughtError = true
    }

    #expect(events.count == 1)
    #expect(events[0].data == "test")
    #expect(caughtError)
  }

  @Test func testExtremelyLongLine() async throws {
    // Generate a very long line
    let longData = String(repeating: "a", count: 10000)
    let input = "data: \(longData)\n\n"

    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data.count == longData.count)
    #expect(events[0].data == longData)
  }

  @Test func testMultipleColonsInLine() async throws {
    let input = "data: value:with:colons\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "value:with:colons")
  }

  @Test func testIdWithColonAndSpace() async throws {
    let input = "id: id:with:colons \ndata: value\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].id == "id:with:colons ")
  }

  @Test func testChunkedDelivery() async throws {
    let parser = EventSourceParser()

    // Create multiple chunks that form a complete event
    let chunks = [
      "data: part",
      " 1\ndata: part 2",
      "\nevent: update\n",
      "id: 123\n\n",
    ]

    var allEvents: [ServerSentEvent] = []

    // Process each chunk separately
    for chunk in chunks {
      let byteStream = AsyncStream<UInt8> { continuation in
        for byte in byteSequence(from: chunk) {
          continuation.yield(byte)
        }
        continuation.finish()
      }

      let chunkEvents = try await withTimeout(
        timeoutMessage: "Timeout waiting for chunked delivery events",
        defaultValue: [ServerSentEvent]()
      ) {
        var collectedEvents: [ServerSentEvent] = []
        for try await event in await parser.parse(byteStream: byteStream) {
          collectedEvents.append(event)
        }
        return collectedEvents
      }
      allEvents.append(contentsOf: chunkEvents)
    }

    // Check if there's a pending event after processing all chunks
    if let finalEvent = await parser.flushPendingEvent() {
      allEvents.append(finalEvent)
    }

    // Should produce one complete event
    #expect(allEvents.count == 1)
    #expect(allEvents[0].eventType == "update")
    #expect(allEvents[0].data == "part 1\npart 2")
    #expect(allEvents[0].id == "123")
  }

  @Test func testEventFieldOrder() async throws {
    // Test that field order doesn't matter - should process fields correctly regardless of order
    let input = "id: 1\ndata: first line\nevent: update\ndata: second line\nretry: 5000\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].eventType == "update")
    #expect(events[0].data == "first line\nsecond line")
    #expect(events[0].id == "1")
    #expect(events[0].retryMs == 5000)
  }

  @Test func testEventWithoutData() async throws {
    // Per the spec, events without data should be ignored
    let input = "event: update\nid: 1\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 0)
  }

  @Test func testEmptyEvent() async throws {
    // An event with empty data field should still be dispatched
    let input = "data:\n\n"
    let events = try await parseEvents(from: input)

    #expect(events.count == 1)
    #expect(events[0].data == "")
  }

  @Test func testMultipleStreams() async throws {
    // Test that the parser can be reused for multiple streams
    let parser = EventSourceParser()

    // First stream
    let input1 = "id: 1\ndata: first stream\n\n"
    var events = try await parseEvents(from: input1, using: parser)

    #expect(events.count == 1)
    #expect(events[0].id == "1")
    #expect(events[0].data == "first stream")

    // Second stream should preserve the last event ID
    let input2 = "data: second stream\n\n"
    events = try await parseEvents(from: input2, using: parser)

    #expect(events.count == 1)
    #expect(events[0].id == "1")  // ID persists from previous stream
    #expect(events[0].data == "second stream")

    // Third stream with new ID
    let input3 = "id: 3\ndata: third stream\n\n"
    events = try await parseEvents(from: input3, using: parser)

    #expect(events.count == 1)
    #expect(events[0].id == "3")
    #expect(events[0].data == "third stream")
  }

  // MARK: - Helper Methods

  /// Converts a string to a byte sequence for testing
  func byteSequence(from string: String) -> [UInt8] {
    return Array(string.utf8)
  }

  /// Helper to run parser on a string input and collect all events
  func parseEvents(from input: String, using parser: EventSourceParser = EventSourceParser())
    async throws -> [ServerSentEvent]
  {
    let bytes = byteSequence(from: input)
    let byteStream = AsyncStream<UInt8> { continuation in
      for byte in bytes {
        continuation.yield(byte)
      }
      continuation.finish()
    }

    return try await withTimeout(
      timeoutMessage: "Timeout waiting for parseEvents to complete",
      defaultValue: [ServerSentEvent]()
    ) {
      var events: [ServerSentEvent] = []
      for try await event in await parser.parse(byteStream: byteStream) {
        events.append(event)
      }
      return events
    }
  }
}
