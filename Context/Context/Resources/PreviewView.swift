// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AVKit
import ContextCore
import HighlightSwift
import SwiftUI
import WebKit
import os

struct PreviewView: View {
  private static let logger = Logger(subsystem: "com.indragie.Context", category: "PreviewView")
  let resource: EmbeddedResource

  var body: some View {
    switch resource {
    case .text(let textContent):
      if let mimeType = textContent.mimeType {
        if mimeType == "text/html" {
          HTMLPreview(html: textContent.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          TextPreview(text: textContent.text, mimeType: mimeType)
        }
      } else {
        TextPreview(text: textContent.text, mimeType: nil)
      }

    case .blob(let blobContent):
      if let mimeType = blobContent.mimeType {
        if mimeType.starts(with: "image/") {
          ImagePreview(data: blobContent.blob)
        } else if mimeType.starts(with: "video/") || mimeType.starts(with: "audio/") {
          MediaPreview(data: blobContent.blob, mimeType: mimeType)
        } else {
          // Fallback to QuickLook for other blob types
          QuickLookFallbackPreview(resource: resource)
        }
      } else {
        QuickLookFallbackPreview(resource: resource)
      }
    }
  }
}

// MARK: - Text Preview with Syntax Highlighting

struct TextPreview: View {
  let text: String
  let mimeType: String?
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    // Check text size before rendering
    if text.utf8.count > 5_000_000 {  // 5MB threshold
      ContentUnavailableView(
        "File Too Large",
        systemImage: "doc.text.magnifyingglass",
        description: Text(
          "This file is too large to preview. Use the Save button to view it in an external editor."
        )
      )
    } else {
      // Use NSTextView for better performance with large text
      HighPerformanceTextView(text: text, mimeType: mimeType, colorScheme: colorScheme)
        .background(Color(NSColor.textBackgroundColor))
    }
  }
}

// High-performance text view using NSTextView
struct HighPerformanceTextView: NSViewRepresentable {
  let text: String
  let mimeType: String?
  let colorScheme: ColorScheme

  private static let highlight = Highlight()

  func makeNSView(context: NSViewRepresentableContext<HighPerformanceTextView>) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()

    if let textView = scrollView.documentView as? NSTextView {
      setupTextView(textView)

      // Set initial text without highlighting for immediate display
      textView.string = text

      // Apply monospace font to initial text
      if let textStorage = textView.textStorage, let font = textView.font {
        let range = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttribute(.font, value: font, range: range)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
      }

      // Start async highlighting
      context.coordinator.startHighlighting(
        text: text, colorScheme: colorScheme, textView: textView, mimeType: mimeType)
    }

    return scrollView
  }

  func updateNSView(
    _ scrollView: NSScrollView, context: NSViewRepresentableContext<HighPerformanceTextView>
  ) {
    guard let textView = scrollView.documentView as? NSTextView else { return }

    // Only update if text changed
    if textView.string != text {
      textView.string = text

      // Apply monospace font to new text
      if let textStorage = textView.textStorage, let font = textView.font {
        let range = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttribute(.font, value: font, range: range)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
      }

      context.coordinator.startHighlighting(
        text: text, colorScheme: colorScheme, textView: textView, mimeType: mimeType)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  private func setupTextView(_ textView: NSTextView) {
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = true
    textView.importsGraphics = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.usesAdaptiveColorMappingForDarkAppearance = true

    // Match SwiftUI's .system(.body, design: .monospaced) font
    let fontSize = NSFont.systemFontSize
    textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)

    // Apply font to existing text
    if let textStorage = textView.textStorage {
      let range = NSRange(location: 0, length: textStorage.length)
      textStorage.addAttribute(.font, value: textView.font!, range: range)
    }

    textView.backgroundColor = .clear
    textView.textContainerInset = NSSize(width: 16, height: 16)
  }

  class Coordinator {
    private var highlightingTask: Task<Void, Never>?

    func startHighlighting(text: String, colorScheme: ColorScheme, textView: NSTextView, mimeType: String?) {
      // Cancel any existing highlighting task
      highlightingTask?.cancel()

      // Don't highlight very large files (> 1MB) for performance
      guard text.utf8.count < 1_000_000 else { return }
      
      // Skip highlighting for text/plain content
      guard mimeType != "text/plain" else { return }

      highlightingTask = Task.detached(priority: .userInitiated) {
        do {
          let highlighted = try await HighPerformanceTextView.highlight
            .attributedText(text, colors: colorScheme == .dark ? .dark(.github) : .light(.github))

          // Check if task was cancelled
          if Task.isCancelled { return }

          await MainActor.run {
            // Update text view with highlighted content
            if let textStorage = textView.textStorage {
              textStorage.beginEditing()

              // Set the highlighted text
              textStorage.setAttributedString(NSAttributedString(highlighted))

              // Override the font to ensure monospace is preserved
              let fullRange = NSRange(location: 0, length: textStorage.length)
              textStorage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                range: fullRange)

              textStorage.endEditing()
            }
          }
        } catch {
          // Highlighting failed, keep plain text
        }
      }
    }

    deinit {
      highlightingTask?.cancel()
    }
  }
}

// MARK: - HTML Preview

struct HTMLPreview: NSViewRepresentable {
  let html: String

  func makeNSView(context: NSViewRepresentableContext<HTMLPreview>) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.translatesAutoresizingMaskIntoConstraints = false
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: NSViewRepresentableContext<HTMLPreview>) {
    webView.loadHTMLString(html, baseURL: nil)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator: NSObject, WKNavigationDelegate {
    // Implement navigation delegate methods if needed
  }
}

// MARK: - Image Preview

struct ImagePreview: View {
  let data: Data
  @State private var nsImage: NSImage?

  var body: some View {
    Group {
      if let nsImage = nsImage {
        ScrollView([.horizontal, .vertical]) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.controlBackgroundColor))
      } else {
        VStack {
          Image(systemName: "photo")
            .font(.largeTitle)
            .foregroundColor(.secondary)
          Text("Unable to load image")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear {
      loadImage()
    }
  }

  private func loadImage() {
    if let image = NSImage(data: data) {
      nsImage = image
    }
  }
}

// MARK: - Media Preview (Audio/Video)

struct MediaPreview: View {
  private static let logger = Logger(subsystem: "com.indragie.Context", category: "MediaPreview")
  let data: Data
  let mimeType: String
  @State private var player: AVPlayer?
  @State private var tempURL: URL?

  var body: some View {
    Group {
      if let player = player {
        VideoPlayer(player: player)
          .onDisappear {
            player.pause()
            cleanupTempFile()
          }
      } else {
        VStack {
          Image(systemName: mimeType.starts(with: "video/") ? "video" : "speaker.wave.2")
            .font(.largeTitle)
            .foregroundColor(.secondary)
          Text("Preparing media...")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear {
      loadMedia()
    }
  }

  private func loadMedia() {
    // Create a temporary file for the media data
    let tempDir = FileManager.default.temporaryDirectory
    let fileName = UUID().uuidString + mediaFileExtension
    let tempURL = tempDir.appendingPathComponent(fileName)

    do {
      try data.write(to: tempURL)
      self.tempURL = tempURL
      self.player = AVPlayer(url: tempURL)
    } catch {
      MediaPreview.logger.error("Failed to create temporary media file: \(error)")
    }
  }

  private func cleanupTempFile() {
    if let tempURL = tempURL {
      try? FileManager.default.removeItem(at: tempURL)
    }
  }

  private var mediaFileExtension: String {
    switch mimeType {
    case "video/mp4":
      return ".mp4"
    case "video/quicktime":
      return ".mov"
    case "video/x-msvideo":
      return ".avi"
    case "video/webm":
      return ".webm"
    case "audio/mpeg", "audio/mp3":
      return ".mp3"
    case "audio/wav":
      return ".wav"
    case "audio/ogg":
      return ".ogg"
    case "audio/aac":
      return ".aac"
    case "audio/flac":
      return ".flac"
    default:
      return ".media"
    }
  }
}

// MARK: - QuickLook Fallback

struct QuickLookFallbackPreview: View {
  let resource: EmbeddedResource
  @State private var previewURL: URL?

  var body: some View {
    Group {
      if let url = previewURL {
        QuickLookPreview(url: url)
      } else {
        ProgressView()
          .controlSize(.regular)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear {
      createPreviewURL()
    }
    .onDisappear {
      cleanupPreviewURL()
    }
  }

  private func createPreviewURL() {
    if let url = QuickLookPreview.createTemporaryURL(for: resource) {
      previewURL = url
    }
  }

  private func cleanupPreviewURL() {
    if let url = previewURL {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
