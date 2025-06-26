import AppKit
import ComposableArchitecture
import ImageIO
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FeedbackView: View {
  let store: StoreOf<FeedbackFeature>
  @State private var urlToPreview: URL?
  @Environment(\.dismissWindow) private var dismissWindow
  @State private var shouldFocusMessage = true

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Form {
        messageSection(viewStore)
        contactInfoSection(viewStore)
        screenshotSection(viewStore)
      }
      .formStyle(.grouped)
      .fixedSize()
      .scrollDisabled(true)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          cancelButton
        }

        ToolbarItem(placement: .confirmationAction) {
          sendButton(viewStore)
        }
      }
      .alert(
        "Feedback Sent",
        isPresented: submissionSuccessBinding(viewStore)
      ) {
        Button("OK") {
          viewStore.send(.dismissSuccess)
          dismissWindow(id: "feedback")
        }
      } message: {
        Text(
          "Thank you for your feedback! We appreciate you taking the time to help us improve Context."
        )
      }
      .alert(
        "Error Sending Feedback",
        isPresented: submissionErrorBinding(viewStore)
      ) {
        Button("OK") {
          viewStore.send(.dismissError)
        }
      } message: {
        if let error = viewStore.submissionError {
          Text(error)
        }
      }
      .onAppear {
        viewStore.send(.onAppear)
      }
      .onDisappear {
        cleanupTempFile()
        viewStore.send(.resetForm)
      }
    }
  }
}

// MARK: - View Components

extension FeedbackView {
  @ViewBuilder
  private func messageSection(_ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>)
    -> some View
  {
    Section(
      content: {
        messageField(viewStore)
      },
      header: {
        Text("Message")
      })
  }

  @ViewBuilder
  private func contactInfoSection(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> some View {
    Section(
      content: {
        VStack(alignment: .leading, spacing: 12) {
          TextField(
            "Name",
            text: nameBinding(viewStore),
            prompt: Text("Your name")
          )
          .textFieldStyle(.roundedBorder)
          VStack(alignment: .leading, spacing: 6) {
            TextField(
              "Email", text: emailBinding(viewStore), prompt: Text("your@email.com")
            )
            .textFieldStyle(.roundedBorder)

            if !viewStore.isEmailValid {
              Text("Please enter a valid email address")
                .font(.caption)
                .foregroundStyle(.red)
            }
          }
        }
      },
      header: {
        Text("Contact Information (optional)")
      })
  }

  @ViewBuilder
  private func screenshotSection(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> some View {
    Section(
      content: {
        VStack(alignment: .leading, spacing: 12) {
          screenshotToggle(viewStore)
          screenshotPreview(viewStore)
        }
      },
      header: {
        Text("Attachments")
      })
  }

  @ViewBuilder
  private func screenshotToggle(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> some View {
    Toggle(
      isOn: includeScreenshotBinding(viewStore)
    ) {
      Text("Include Screenshot")
    }
  }

  @ViewBuilder
  private func screenshotPreview(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> some View {
    HStack(spacing: 12) {
      screenshotThumbnail(viewStore)
      screenshotControls(viewStore)
      Spacer()
    }
  }

  @ViewBuilder
  private func screenshotThumbnail(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> some View {
    Button(action: {
      if viewStore.includeScreenshot, let screenshot = viewStore.screenshotImage {
        urlToPreview = saveCGImageToTempFile(screenshot)
      }
    }) {
      if viewStore.includeScreenshot, let screenshot = viewStore.screenshotImage {
        Image(screenshot, scale: 1.0, label: Text("Screenshot"))
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120, height: 80)
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(Color(NSColor.separatorColor), lineWidth: 1)
          )
      } else {
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(NSColor.controlBackgroundColor))
          .frame(width: 120, height: 80)
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(Color(NSColor.separatorColor), lineWidth: 1)
          )
          .overlay(
            Image(systemName: "photo")
              .font(.system(size: 30))
              .foregroundColor(.secondary)
          )
      }
    }
    .buttonStyle(.plain)
    .disabled(!viewStore.includeScreenshot || viewStore.screenshotImage == nil)
    .quickLookPreview($urlToPreview)
    .onChange(of: urlToPreview) { oldValue, _ in
      if let oldURL = oldValue {
        try? FileManager.default.removeItem(at: oldURL)
      }
    }
  }

  @ViewBuilder
  private func screenshotControls(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if viewStore.includeScreenshot && viewStore.screenshotImage != nil {
        Text("Screenshot captured")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        Button("Replace image...") {
          viewStore.send(.selectCustomScreenshot)
        }
        .controlSize(.small)
        .disabled(!viewStore.includeScreenshot)

        if viewStore.customScreenshotURL != nil {
          Button("Use original") {
            viewStore.send(.restoreOriginalScreenshot)
          }
          .controlSize(.small)
          .disabled(!viewStore.includeScreenshot)
        }
      }
    }
  }

  private var cancelButton: some View {
    Button("Cancel") {
      dismissWindow(id: "feedback")
    }
    .keyboardShortcut(.cancelAction)
  }

  private func sendButton(_ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>)
    -> some View
  {
    Button(action: {
      viewStore.send(.submitFeedback)
    }) {
      Label("Send", systemImage: "paperplane.fill")
        .labelStyle(.iconOnly)
    }
    .keyboardShortcut(.defaultAction)
    .disabled(!viewStore.canSubmit)
  }
}

// MARK: - Bindings

extension FeedbackView {
  private func messageBinding(_ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>)
    -> Binding<String>
  {
    viewStore.binding(
      get: \.message,
      send: FeedbackFeature.Action.messageChanged
    )
  }

  private func nameBinding(_ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>)
    -> Binding<String>
  {
    viewStore.binding(
      get: \.name,
      send: FeedbackFeature.Action.nameChanged
    )
  }

  private func emailBinding(_ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>)
    -> Binding<String>
  {
    viewStore.binding(
      get: \.email,
      send: FeedbackFeature.Action.emailChanged
    )
  }

  private func includeScreenshotBinding(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> Binding<Bool> {
    viewStore.binding(
      get: \.includeScreenshot,
      send: FeedbackFeature.Action.includeScreenshotToggled
    )
  }

  private func submissionSuccessBinding(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> Binding<Bool> {
    viewStore.binding(
      get: \.submissionSuccess,
      send: { _ in .dismissSuccess }
    )
  }

  private func submissionErrorBinding(
    _ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>
  ) -> Binding<Bool> {
    viewStore.binding(
      get: { $0.submissionError != nil },
      send: { _ in .dismissError }
    )
  }
}

// MARK: - Helper Methods

extension FeedbackView {
  private func cleanupTempFile() {
    if let url = urlToPreview {
      try? FileManager.default.removeItem(at: url)
      urlToPreview = nil
    }
  }

  @ViewBuilder
  private func messageField(_ viewStore: ViewStore<FeedbackFeature.State, FeedbackFeature.Action>)
    -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      MultilineTextField(
        text: messageBinding(viewStore),
        shouldFocus: shouldFocusMessage,
        onFocusChange: { focused in
          if !focused {
            shouldFocusMessage = false
          }
        }
      )
      .frame(minHeight: 100, idealHeight: 120, maxHeight: 200)

      if !viewStore.isMessageValid && !viewStore.message.isEmpty {
        Text("Please enter a message")
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }
}

#Preview {
  FeedbackView(
    store: Store(initialState: FeedbackFeature.State()) {
      FeedbackFeature()
    }
  )
}

// MARK: - Custom Text Editor

struct MultilineTextField: NSViewRepresentable {
  @Binding var text: String
  let shouldFocus: Bool
  let onFocusChange: (Bool) -> Void

  func makeNSView(context: NSViewRepresentableContext<MultilineTextField>) -> NSScrollView {
    let scrollView = NSScrollView()

    // Configure scroll view first
    scrollView.borderType = .bezelBorder
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.focusRingType = .exterior

    // Create and configure text view
    let textView = NSTextView()
    textView.string = text
    textView.delegate = context.coordinator
    textView.font = .systemFont(ofSize: NSFont.systemFontSize)
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.allowsUndo = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.isFieldEditor = false
    textView.usesFindBar = false
    textView.isAutomaticSpellingCorrectionEnabled = true
    textView.isGrammarCheckingEnabled = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.drawsBackground = true
    textView.backgroundColor = .textBackgroundColor
    textView.textColor = .textColor

    // Set up the text container
    textView.textContainer?.containerSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.lineFragmentPadding = 5
    textView.minSize = CGSize(width: 0, height: 0)
    textView.maxSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]

    // Set the text view as document view
    scrollView.documentView = textView

    // Store text view reference
    context.coordinator.textView = textView

    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: NSViewRepresentableContext<MultilineTextField>)
  {
    guard let textView = context.coordinator.textView else { return }

    if textView.string != text {
      textView.string = text
    }

    // Focus only once on initial load
    if shouldFocus && !context.coordinator.hasSetInitialFocus {
      DispatchQueue.main.async {
        textView.window?.makeFirstResponder(textView)
        context.coordinator.hasSetInitialFocus = true
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MultilineTextField
    var hasSetInitialFocus = false
    weak var textView: NSTextView?

    init(_ parent: MultilineTextField) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }

    func textDidBeginEditing(_ notification: Notification) {
      parent.onFocusChange(true)
    }

    func textDidEndEditing(_ notification: Notification) {
      parent.onFocusChange(false)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      // Handle tab key
      if commandSelector == #selector(NSTextView.insertTab(_:)) {
        textView.window?.makeFirstResponder(textView.nextValidKeyView)
        return true
      }
      // Handle shift-tab key
      if commandSelector == #selector(NSTextView.insertBacktab(_:)) {
        textView.window?.makeFirstResponder(textView.previousValidKeyView)
        return true
      }
      return false
    }
  }
}

// MARK: - Helpers

private func saveCGImageToTempFile(_ cgImage: CGImage) -> URL? {
  let tempURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("screenshot-\(UUID().uuidString).png")

  guard
    let destination = CGImageDestinationCreateWithURL(
      tempURL as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else {
    return nil
  }

  CGImageDestinationAddImage(destination, cgImage, nil)

  guard CGImageDestinationFinalize(destination) else {
    return nil
  }

  return tempURL
}
