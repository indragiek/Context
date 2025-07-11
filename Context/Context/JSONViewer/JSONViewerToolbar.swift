// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import os

struct JSONViewerToolbar: View {
  private static let logger = Logger(subsystem: "com.indragie.Context", category: "JSONViewerToolbar")
  @Binding var selectedTab: JSONValueView.Tab
  @Binding var searchText: String
  @Binding var showCopiedMessage: Bool
  let jsonValue: JSONValue

  @State private var shareURL: URL?
  @State private var quickLookURL: URL?

  var body: some View {
    GeometryReader { geometry in
      // When width is too small, switch to left-aligned layout
      if geometry.size.width < 700 {
        // Compact layout - everything left aligned
        HStack(spacing: 8) {
          ToggleButton(selection: $selectedTab)

          Spacer()

          toolbarButtons
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor))
      } else {
        // Regular layout - toggle buttons centered
        ZStack {
          // Center - Toggle buttons (in ZStack so they're truly centered)
          ToggleButton(selection: $selectedTab)

          // Right side - Search field and buttons (aligned to trailing edge)
          HStack {
            Spacer()
            toolbarButtons
          }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor))
      }
    }
    .frame(height: 44)  // Fixed height for the toolbar
    .onAppear {
      createShareURL()
    }
    .onDisappear {
      cleanupShareURL()
    }
  }

  @ViewBuilder
  private var toolbarButtons: some View {
    HStack(spacing: 8) {
      // Search field
      SearchField(text: $searchText)
        .frame(width: 140)

      // "Copied!" indicator
      if showCopiedMessage {
        Text("Copied!")
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)
          .transition(
            .asymmetric(
              insertion: .move(edge: .trailing).combined(with: .opacity),
              removal: .move(edge: .leading).combined(with: .opacity)
            )
          )
          .layoutPriority(1)
      }

      // Copy button
      Button(action: {
        copyFullJSON()
      }) {
        Image(systemName: "doc.on.doc")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.secondary)
          .frame(width: 24, height: 24)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.clear)
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Copy JSON")

      // Save button
      Button(action: {
        saveJSON()
      }) {
        Image(systemName: "square.and.arrow.down")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.secondary)
          .frame(width: 24, height: 24)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.clear)
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Save JSON")

      // Share button
      if let shareURL = shareURL {
        ShareLink(item: shareURL) {
          Image(systemName: "square.and.arrow.up")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Share JSON")
      } else {
        Button(action: {}) {
          Image(systemName: "square.and.arrow.up")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary.opacity(0.5))
            .frame(width: 24, height: 24)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(true)
        .help("Share JSON")
      }

      // Expand button (QuickLook)
      if shareURL != nil {
        Button(action: {
          quickLookURL = shareURL
        }) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand preview")
        .quickLookPreview($quickLookURL)
      } else {
        Button(action: {}) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary.opacity(0.5))
            .frame(width: 24, height: 24)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(true)
        .help("Expand preview")
      }
    }
  }

  private func copyFullJSON() {
    if let jsonString = JSONUtility.prettyString(from: jsonValue, escapeSlashes: true) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(jsonString, forType: .string)

      // Show copied message with animation
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        showCopiedMessage = true
      }

      // Hide message after 1.5 seconds
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          showCopiedMessage = false
        }
      }
    }
  }

  private func saveJSON() {
    let savePanel = NSSavePanel()
    savePanel.nameFieldStringValue = "data.json"
    savePanel.allowedContentTypes = [.json]
    savePanel.canCreateDirectories = true
    savePanel.showsTagField = false
    savePanel.isExtensionHidden = false

    savePanel.begin { response in
      if response == .OK, let url = savePanel.url {
        do {
          let data = try JSONUtility.prettyData(from: jsonValue, escapeSlashes: true)
          try data.write(to: url)
        } catch {
          JSONViewerToolbar.logger.error("Failed to save JSON: \(error)")
        }
      }
    }
  }

  private func createShareURL() {
    let tempDir = FileManager.default.temporaryDirectory
    let tempURL = tempDir.appendingPathComponent("data.json")

    do {
      let data = try JSONUtility.prettyData(from: jsonValue, escapeSlashes: true)
      try data.write(to: tempURL)
      shareURL = tempURL
    } catch {
      JSONViewerToolbar.logger.error("Failed to create share URL: \(error)")
    }
  }

  private func cleanupShareURL() {
    if let shareURL = shareURL {
      try? FileManager.default.removeItem(at: shareURL)
      self.shareURL = nil
    }
    quickLookURL = nil
  }
}
