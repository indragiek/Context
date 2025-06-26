import AppKit
import ComposableArchitecture
import Dependencies
import Foundation
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import os

#if !SENTRY_DISABLED
  import Sentry
#endif

@Reducer
struct FeedbackFeature {
  private let logger: Logger

  init(logger: Logger = Logger(subsystem: "com.indragie.Context", category: "FeedbackFeature")) {
    self.logger = logger
  }

  @ObservableState
  struct State: Equatable {
    var message: String = ""
    var name: String = ""
    var email: String = ""
    var includeScreenshot: Bool = false
    var screenshotImage: CGImage?
    var preCapturedScreenshot: CGImage?
    var customScreenshotURL: URL?
    var isSubmitting: Bool = false
    var submissionError: String?
    var submissionSuccess: Bool = false

    var isMessageValid: Bool {
      !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isEmailValid: Bool {
      email.isEmpty || isValidEmail(email)
    }

    var canSubmit: Bool {
      isMessageValid && isEmailValid && !isSubmitting
    }

    private func isValidEmail(_ email: String) -> Bool {
      let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
      let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
      return emailPredicate.evaluate(with: email)
    }
  }

  enum Action {
    case onAppear
    case messageChanged(String)
    case nameChanged(String)
    case emailChanged(String)
    case includeScreenshotToggled(Bool)
    case captureScreenshot
    case screenshotCaptured(CGImage?)
    case selectCustomScreenshot
    case customScreenshotSelected(URL?)
    case restoreOriginalScreenshot
    case submitFeedback
    case feedbackSubmitted(Result<Void, any Error>)
    case dismissError
    case dismissSuccess
    case resetForm
  }

  @Dependency(\.dismiss) var dismiss

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        // No longer capture screenshot on appear
        return .none

      case let .messageChanged(message):
        state.message = message
        return .none

      case let .nameChanged(name):
        state.name = name
        return .none

      case let .emailChanged(email):
        state.email = email
        return .none

      case let .includeScreenshotToggled(include):
        state.includeScreenshot = include
        if !include {
          state.screenshotImage = nil
          state.customScreenshotURL = nil
        } else {
          // Capture screenshot when toggled on
          return .run { send in
            let screenshot = await captureScreenshotWithScreenCaptureKit()
            await send(.screenshotCaptured(screenshot))
          }
        }
        return .none

      case .captureScreenshot:
        // No longer needed - screenshot is pre-captured
        return .none

      case let .screenshotCaptured(screenshot):
        state.screenshotImage = screenshot
        state.preCapturedScreenshot = screenshot
        return .none

      case .selectCustomScreenshot:
        return .run { send in
          let url = await MainActor.run {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.message = "Select a screenshot to include with your feedback"

            let response = panel.runModal()
            return response == .OK ? panel.url : nil
          }
          await send(.customScreenshotSelected(url))
        }

      case let .customScreenshotSelected(url):
        guard let url = url else { return .none }
        state.customScreenshotURL = url
        // Load CGImage directly from URL
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        {
          state.screenshotImage = cgImage
        }
        return .none

      case .restoreOriginalScreenshot:
        state.screenshotImage = state.preCapturedScreenshot
        state.customScreenshotURL = nil
        return .none

      case .submitFeedback:
        guard state.canSubmit else { return .none }

        state.isSubmitting = true
        state.submissionError = nil

        return .run {
          [
            message = state.message,
            name = state.name.isEmpty ? nil : state.name,
            email = state.email.isEmpty ? nil : state.email,
            screenshotImage = state.includeScreenshot ? state.screenshotImage : nil
          ] send in
          var attachments = [Data]()
          if let screenshotImage = screenshotImage {
            // Convert CGImage to PNG data
            let data = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(
              data as CFMutableData,
              UTType.png.identifier as CFString,
              1,
              nil
            ) {
              CGImageDestinationAddImage(destination, screenshotImage, nil)
              if CGImageDestinationFinalize(destination) {
                attachments.append(data as Data)
              }
            }
          }

          #if !SENTRY_DISABLED
            SentrySDK.capture(
              feedback: SentryFeedback(
                message: message,
                name: name,
                email: email,
                source: .custom,
                attachments: attachments
              ))
          #endif
          await send(.feedbackSubmitted(.success(())))
        }

      case let .feedbackSubmitted(result):
        state.isSubmitting = false
        switch result {
        case .success:
          state.submissionSuccess = true
        case .failure(let error):
          state.submissionError = error.localizedDescription
        }
        return .none

      case .dismissError:
        state.submissionError = nil
        return .none

      case .dismissSuccess:
        state.submissionSuccess = false
        return .none

      case .resetForm:
        // Reset all form fields to initial state
        state.message = ""
        state.name = ""
        state.email = ""
        state.includeScreenshot = true
        state.screenshotImage = nil
        state.customScreenshotURL = nil
        state.submissionError = nil
        state.submissionSuccess = false
        return .none
      }
    }
  }

  private func captureScreenshotWithScreenCaptureKit() async -> CGImage? {
    do {
      let content = try await SCShareableContent.current
      guard
        let mainWindow = content.windows.first(where: { window in
          window.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            && window.title != "Give Feedback" && window.isOnScreen
        })
      else {
        return nil
      }

      let filter = SCContentFilter(desktopIndependentWindow: mainWindow)
      let config = SCStreamConfiguration()
      config.width = Int(mainWindow.frame.width * 2)  // Retina scale
      config.height = Int(mainWindow.frame.height * 2)  // Retina scale
      config.capturesAudio = false
      config.showsCursor = false

      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: config
      )

      return image
    } catch let error {
      // Fallback to traditional method if ScreenCaptureKit fails
      logger.error("\(error)")
      return await Self.captureScreenshotFallback()
    }
  }

  @MainActor
  private static func captureScreenshotFallback() -> CGImage? {
    guard
      let mainWindow = NSApp.windows.first(where: { window in
        window.isVisible && window.title != "Give Feedback" && window.contentViewController != nil
      }),
      let contentView = mainWindow.contentView
    else {
      return nil
    }

    let bounds = contentView.bounds
    guard let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
      return nil
    }

    contentView.cacheDisplay(in: bounds, to: bitmapRep)

    let image = NSImage(size: bounds.size)
    image.addRepresentation(bitmapRep)

    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }

    return cgImage
  }
}
