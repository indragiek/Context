// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI
import ContextCore

struct ConnectionErrorDetailView: View {
  let errors: [ConnectionError]
  @Environment(\.dismiss) private var dismiss
  @State private var expandedErrors: Set<UUID> = []

  private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .medium
    return formatter
  }()

  private func expandAll() {
    expandedErrors = Set(errors.map(\.id))
  }

  private func collapseAll() {
    expandedErrors.removeAll()
  }

  private func copyAll() {
    let allLogs = errors.reversed().map { error in
      let timestamp = dateFormatter.string(from: error.timestamp)
      var logLine = "\(timestamp): \(error.errorDescription)"
      if let json = error.json,
         let jsonString = JSONUtility.prettyString(from: json, escapeSlashes: true) {
        logLine += "\n\(jsonString)"
      }
      return logLine
    }.joined(separator: "\n\n")
    
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(allLogs, forType: .string)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack(spacing: 16) {
        Button(action: copyAll) {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy All Logs")
        
        Button(action: expandAll) {
          Image(systemName: "arrow.up.backward.and.arrow.down.forward")
        }
        .buttonStyle(.borderless)
        .help("Expand All")
        
        Button(action: collapseAll) {
          Image(systemName: "arrow.down.forward.and.arrow.up.backward")
        }
        .buttonStyle(.borderless)
        .help("Collapse All")
        
        Spacer()

        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
      .padding()
      .background(Color(NSColor.windowBackgroundColor))

      Divider()

      // Error list
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(errors.reversed()) { error in
            ErrorRowView(
              error: error,
              isExpanded: expandedErrors.contains(error.id),
              dateFormatter: dateFormatter
            ) {
              if expandedErrors.contains(error.id) {
                expandedErrors.remove(error.id)
              } else {
                expandedErrors.insert(error.id)
              }
            }
            
            if error.id != errors.first?.id {
              Divider()
                .padding(.horizontal, 16)
            }
          }
        }
        .padding(.vertical, 1)
      }
      .frame(maxHeight: .infinity)
      .background(Color(NSColor.controlBackgroundColor))
    }
    .frame(width: 800, height: 500)
  }
}

struct ErrorRowView: View {
  let error: ConnectionError
  let isExpanded: Bool
  let dateFormatter: DateFormatter
  let onToggle: () -> Void
  
  private func copyError() {
    let timestamp = dateFormatter.string(from: error.timestamp)
    var content = "\(timestamp): \(error.errorDescription)"
    if let json = error.json,
       let jsonString = JSONUtility.prettyString(from: json, escapeSlashes: true) {
      content += "\n\(jsonString)"
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(content, forType: .string)
  }
  
  private func copyJSON(for value: JSONValue) {
    if let jsonString = JSONUtility.prettyString(from: value, escapeSlashes: true) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(jsonString, forType: .string)
    }
  }
  
  var body: some View {
    VStack(spacing: 0) {
      // Collapsed/Summary Row
      HStack(alignment: .top, spacing: 12) {
        // Disclosure triangle
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .frame(width: 12)
          .padding(.top, 5)
        
        // Timestamp
        Text(dateFormatter.string(from: error.timestamp))
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 100, alignment: .leading)
          .fixedSize(horizontal: true, vertical: false)
          .padding(.top, 3)
        
        // Error description
        Text(error.errorDescription)
          .font(.system(size: 13, design: .monospaced))
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .lineLimit(isExpanded ? nil : 2)
          .padding(.vertical, 3)
        
        // JSON indicator
        if error.json != nil {
          Text("{}")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
            .padding(.top, 3)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
      .onTapGesture {
        onToggle()
      }
      .contextMenu {
        Button("Copy") {
          copyError()
        }
      }
      
      // Expanded Details
      if isExpanded, let json = error.json {
        VStack(alignment: .leading, spacing: 8) {
          Divider()
            .padding(.horizontal, 16)
          
          ZStack(alignment: .topTrailing) {
            if let jsonString = JSONUtility.prettyString(from: json) {
              JSONContentView(
                contentLines: jsonString.components(separatedBy: .newlines),
                searchText: "",
                isSearchActive: false
              )
              .padding(.leading, 44)
              .padding(.trailing, 16)
              .background(Color(NSColor.textBackgroundColor).opacity(0.5))
              .cornerRadius(6)
            }
            
            Button(action: { copyJSON(for: json) }) {
              Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 6)
            .padding(.top, 6)
            .help("Copy JSON")
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 12)
        }
      }
    }
  }
}
