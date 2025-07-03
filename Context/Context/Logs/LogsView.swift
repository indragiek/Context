// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI

struct LogsView: View {
  let store: StoreOf<LogsFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Group {
        if viewStore.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewStore.filteredLogs.isEmpty {
          if let error = viewStore.error {
            ContentUnavailableView(
              "Failed to Load Logs",
              systemImage: "exclamationmark.triangle",
              description: Text(error)
            )
          } else {
            ContentUnavailableView(
              viewStore.searchQuery.isEmpty ? "No Logs" : "No Results",
              systemImage: "doc.text",
              description: Text(
                viewStore.searchQuery.isEmpty
                  ? "No logs available" : "No logs match '\(viewStore.searchQuery)'"
              )
            )
          }
        } else {
          ScrollViewReader { proxy in
            Table(
              viewStore.filteredLogs,
              selection: viewStore.binding(
                get: \.selectedLogIDs,
                send: LogsFeature.Action.logSelected
              )
            ) {
              TableColumn("") { cachedLogEntry in
                let logEntry = cachedLogEntry.logEntry
                HStack(alignment: .center) {
                  logMessageView(for: logEntry.params)
                    .textSelection(.enabled)

                  Spacer()

                  LogLevelLabel(
                    level: logEntry.params.level,
                    isSelected: viewStore.selectedLogIDs.contains(logEntry.id)
                  )

                  Text(logEntry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .id(logEntry.id)
              }
            }
            .tableColumnHeaders(.hidden)
            .contextMenu(forSelectionType: LogEntry.ID.self) { items in
              if let logID = items.first,
                let cachedLogEntry = viewStore.filteredLogs.first(where: { $0.id == logID })
              {
                let logEntry = cachedLogEntry.logEntry
                Button("Copy Message") {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(
                    logDisplayText(for: logEntry.params), forType: .string)
                }

                Button("Copy JSON") {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(cachedLogEntry.jsonString, forType: .string)
                }
              }
            }
            .onChange(of: viewStore.searchQuery) { _, _ in
              // Reset scroll position to top for any search query change
              if let firstLog = viewStore.filteredLogs.first {
                proxy.scrollTo(firstLog.logEntry.id, anchor: .top)
              }
            }
          }
        }
      }
      .searchable(
        text: viewStore.binding(
          get: \.searchQuery,
          send: LogsFeature.Action.searchQueryChanged
        ), prompt: "Search logs..."
      )
      .onAppear {
        viewStore.send(.onAppear)
      }
      .onDisappear {
        viewStore.send(.onDisappear)
      }
    }
  }

  @ViewBuilder
  private func logMessageView(for log: LoggingMessageNotification.Params) -> some View {
    switch log.data {
    case .string(let string):
      Text(string)
        .font(.system(.body, design: .monospaced))
    case .object(let dict):
      // Check for "message" key first
      if let message = dict["message"], case .string(let msgString) = message {
        Text(msgString)
          .font(.system(.body, design: .monospaced))
      }
      // Check for "body" key second
      else if let body = dict["body"], case .string(let bodyString) = body {
        Text(bodyString)
          .font(.system(.body, design: .monospaced))
      }
      // No message or body key found, create styled placeholder
      else {
        let sortedKeys = dict.keys.sorted()
        let firstThreeKeys = Array(sortedKeys.prefix(3))
        let remainingCount = max(0, sortedKeys.count - 3)

        HStack(spacing: 0) {
          Text("(no message) ")
            .font(.system(.body, design: .monospaced))
            .italic()
            .foregroundColor(.primary)

          if sortedKeys.isEmpty {
            Text("[empty object]")
              .font(.system(.body, design: .monospaced))
              .foregroundColor(.secondary)
          } else if remainingCount == 0 {
            Text("[\(firstThreeKeys.joined(separator: ", "))]")
              .font(.system(.body, design: .monospaced))
              .foregroundColor(.secondary)
          } else {
            Text(
              "[\(firstThreeKeys.joined(separator: ", ")), and \(remainingCount) other key\(remainingCount == 1 ? "" : "s")]"
            )
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.secondary)
          }
        }
        .lineLimit(1)
        .truncationMode(.tail)
      }
    default:
      // For non-string, non-object data, convert to JSON string representation
      if let data = try? JSONEncoder().encode(log.data),
        let jsonString = String(data: data, encoding: .utf8)
      {
        Text(jsonString)
          .font(.system(.body, design: .monospaced))
      } else {
        Text("Unable to display log data")
          .font(.system(.body, design: .monospaced))
          .foregroundColor(.secondary)
      }
    }
  }

  private func logDisplayText(for log: LoggingMessageNotification.Params) -> String {
    switch log.data {
    case .string(let string):
      return string
    case .object(let dict):
      // Check for "message" key first
      if let message = dict["message"], case .string(let msgString) = message {
        return msgString
      }
      // Check for "body" key second
      if let body = dict["body"], case .string(let bodyString) = body {
        return bodyString
      }

      // No message or body key found, create placeholder
      let sortedKeys = dict.keys.sorted()
      let firstThreeKeys = Array(sortedKeys.prefix(3))
      let remainingCount = max(0, sortedKeys.count - 3)

      if sortedKeys.isEmpty {
        return "(no message) [empty object]"
      } else if remainingCount == 0 {
        return "(no message) [\(firstThreeKeys.joined(separator: ", "))]"
      } else {
        return
          "(no message) [\(firstThreeKeys.joined(separator: ", ")), and \(remainingCount) other key\(remainingCount == 1 ? "" : "s")]"
      }

    default:
      // For non-string, non-object data, convert to JSON string representation
      if let data = try? JSONEncoder().encode(log.data),
        let jsonString = String(data: data, encoding: .utf8)
      {
        return jsonString
      } else {
        return "Unable to display log data"
      }
    }
  }
}

struct LogLevelLabel: View {
  let level: LoggingLevel
  let isSelected: Bool

  init(level: LoggingLevel, isSelected: Bool = false) {
    self.level = level
    self.isSelected = isSelected
  }

  var body: some View {
    Text(level.rawValue.uppercased())
      .font(.caption2)
      .fontWeight(.semibold)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(backgroundColor)
      )
      .foregroundColor(foregroundColor)
  }

  private var backgroundColor: Color {
    if isSelected {
      // Use more opaque backgrounds for better visibility on selection
      switch level {
      case .debug:
        return Color.gray.opacity(0.8)
      case .info, .notice:
        return Color.blue.opacity(0.8)
      case .warning:
        return Color.orange.opacity(0.8)
      case .error:
        return Color.red.opacity(0.8)
      case .critical, .alert, .emergency:
        return Color.red.opacity(0.9)
      }
    } else {
      switch level {
      case .debug:
        return Color.gray.opacity(0.2)
      case .info, .notice:
        return Color.blue.opacity(0.2)
      case .warning:
        return Color.orange.opacity(0.2)
      case .error:
        return Color.red.opacity(0.2)
      case .critical, .alert, .emergency:
        return Color.red.opacity(0.3)
      }
    }
  }

  private var foregroundColor: Color {
    if isSelected {
      // Use white text on selected state for better contrast
      return .white
    } else {
      switch level {
      case .debug:
        return .gray
      case .info, .notice:
        return .blue
      case .warning:
        return .orange
      case .error, .critical, .alert, .emergency:
        return .red
      }
    }
  }
}
