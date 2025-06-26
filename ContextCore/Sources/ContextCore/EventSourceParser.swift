// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// Represents a parsed Server-Sent Event
public struct ServerSentEvent: Sendable {
  /// The event type (defaults to "message" if not specified)
  public let eventType: String
  /// The event data
  public let data: String
  /// Optional event ID
  public let id: String?
  /// Optional reconnection time in milliseconds
  public let retryMs: Int?

  public init(eventType: String = "message", data: String, id: String? = nil, retryMs: Int? = nil) {
    self.eventType = eventType
    self.data = data
    self.id = id
    self.retryMs = retryMs
  }
}

/// Parser for Server-Sent Events streams according to WHATWG specification
/// Processes an AsyncSequence of bytes directly
actor EventSourceParser {
  // Field values for the current event
  private var currentData: [String] = []
  private var currentEventType: String = "message"
  private var currentId: String? = nil
  private var currentRetryMs: Int? = nil

  // Buffer for incomplete lines across chunks
  private var incompleteLineBuffer: [UInt8] = []

  // Last event ID seen, used for reconnection
  private(set) var lastEventId: String? = nil

  /// Parse an AsyncSequence of bytes (e.g., from a network response)
  /// Returns an AsyncThrowingStream of parsed events
  func parse<S: AsyncSequence>(byteStream: S) -> AsyncThrowingStream<ServerSentEvent, Error>
  where S.Element == UInt8 {
    return AsyncThrowingStream { continuation in
      let task = Task {
        var lineBuffer = incompleteLineBuffer
        var sawCR = false

        do {
          for try await byte in byteStream {
            if byte == 0x0A {  // LF (Line Feed)
              if sawCR {
                // This is part of a CRLF sequence, we've already processed the CR
                sawCR = false
                continue
              }
              if let event = processLine(lineBuffer) {
                continuation.yield(event)
              }
              lineBuffer.removeAll(keepingCapacity: true)
            } else if byte == 0x0D {  // CR (Carriage Return)
              sawCR = true

              if let event = processLine(lineBuffer) {
                continuation.yield(event)
              }
              lineBuffer.removeAll(keepingCapacity: true)
            } else {
              // If we saw a CR but the next character is not LF,
              // we need to reset the sawCR flag
              sawCR = false
              lineBuffer.append(byte)
            }
          }

          if !lineBuffer.isEmpty {
            incompleteLineBuffer = lineBuffer
          } else {
            incompleteLineBuffer.removeAll(keepingCapacity: true)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { state in
        if case .cancelled = state {
          task.cancel()
        }
      }
    }
  }

  /// Process a single line (as bytes) from an event stream
  /// - Parameter lineBytes: Bytes making up a single line from the event stream
  /// - Returns: An optional ServerSentEvent if a complete event was parsed
  private func processLine(_ lineBytes: [UInt8]) -> ServerSentEvent? {
    guard let line = String(bytes: lineBytes, encoding: .utf8) else {
      return nil
    }

    if line.isEmpty {
      if !currentData.isEmpty {
        let event = dispatchEvent()
        reset()
        return event
      }
      return nil
    }

    // If the line starts with a colon, it's a comment and should be ignored
    if line.hasPrefix(":") {
      return nil
    }

    var fieldName = ""
    var value = ""

    if let colonIndex = line.firstIndex(of: ":") {
      fieldName = String(line[..<colonIndex])

      let valueStartIndex = line.index(after: colonIndex)
      if valueStartIndex < line.endIndex {
        // If the colon is followed by a space, remove it
        if line[valueStartIndex] == " " {
          value = String(line[line.index(after: valueStartIndex)...])
        } else {
          value = String(line[valueStartIndex...])
        }
      }
    } else {
      // If there's no colon, the entire line is the field name
      // and the value is the empty string
      fieldName = line
      value = ""
    }

    switch fieldName {
    case "event":
      currentEventType = value

    case "data":
      currentData.append(value)

    case "id":
      // If the value contains a null byte, ignore the field
      if !value.contains("\u{0000}") {
        currentId = value
        lastEventId = value
      }

    case "retry":
      // Try to parse the retry value as an integer
      if let retryTimeMs = Int(value) {
        currentRetryMs = retryTimeMs
      }

    default:
      // Unknown field name, ignored as per spec
      break
    }

    return nil
  }

  /// Force dispatch of any pending event data
  /// - Returns: An event if there was pending data, nil otherwise
  func flushPendingEvent() -> ServerSentEvent? {
    guard !currentData.isEmpty else { return nil }

    let event = dispatchEvent()
    reset()
    return event
  }

  /// Dispatch the current event with all accumulated data
  /// - Returns: A ServerSentEvent object
  private func dispatchEvent() -> ServerSentEvent {
    // If the last item in the data buffer ends with a LF, remove it
    var processedData = currentData
    if let lastIndex = processedData.indices.last,
      processedData[lastIndex].hasSuffix("\n")
    {
      processedData[lastIndex] = String(processedData[lastIndex].dropLast())
    }

    let eventData = processedData.joined(separator: "\n")
    let event = ServerSentEvent(
      eventType: currentEventType,
      data: eventData,
      id: currentId,
      retryMs: currentRetryMs
    )

    return event
  }

  /// Reset the parser state while preserving the lastEventId
  func reset() {
    currentData = []
    currentEventType = "message"
    currentRetryMs = nil
    incompleteLineBuffer = []
    // We intentionally don't reset currentId or lastEventId
  }
}
