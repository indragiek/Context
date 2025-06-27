// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import Darwin
import SharingGRDB
import Sparkle
import SwiftUI

#if !SENTRY_DISABLED
  import Sentry
#endif

@main
struct ContextApp: App {
  @State private var oauthHandler = OAuthCallbackHandler.shared
  private let updaterController: SPUStandardUpdaterController

  init() {
    #if !SENTRY_DISABLED
      SentrySDK.start { options in
        options.dsn =
          "https://3fd20401248f7d1fcfed9e0a7ce389ad@o4509521009508352.ingest.us.sentry.io/4509521010229248"
      }
    #endif

    // Disable SIGPIPE - otherwise this crashes the app when a pipe is broken
    signal(SIGPIPE, SIG_IGN)

    updaterController = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    prepareDependencies {
      $0.defaultDatabase = try! appDatabase()
    }
  }

  var body: some Scene {
    WindowGroup {
      RootContentView(
        store: Store(initialState: AppFeature.State()) {
          AppFeature()
        }
      )
      .frame(minWidth: 900, minHeight: 600)
      .onOpenURL { url in
        _ = oauthHandler.handleURL(url)
      }
    }
    .defaultSize(width: 1050, height: 675)
    .commands {
      CommandGroup(replacing: .newItem) {
        // Remove New Window menu item
      }
      CommandGroup(after: .appInfo) {
        CheckForUpdatesView(updater: updaterController.updater)
      }
      CommandGroup(after: .newItem) {
        Button("Add MCP Server...") {
          NotificationCenter.default.post(
            name: .addMCPServer,
            object: nil
          )
        }
        .keyboardShortcut("N", modifiers: [.command, .shift])

        Divider()

        Button("Import MCP Servers...") {
          NotificationCenter.default.post(
            name: .importMCPServers,
            object: nil
          )
        }
        .keyboardShortcut("I", modifiers: [.command, .shift])

        #if !SENTRY_DISABLED
          Divider()

          Button("Give Feedback...") {
            NotificationCenter.default.post(
              name: .giveFeedback,
              object: nil
            )
          }
        #endif
      }
    }

    Settings {
      SettingsView(updater: updaterController.updater)
    }

    #if !SENTRY_DISABLED
      Window("Give Feedback", id: "feedback") {
        FeedbackView(
          store: Store(initialState: FeedbackFeature.State()) {
            FeedbackFeature()
          }
        )
        .navigationTitle("Give Feedback")
        .navigationSubtitle("Help us improve Context by sharing your thoughts")
      }
      .windowResizability(.contentSize)
      .restorationBehavior(.disabled)
    #endif
  }
}

extension Notification.Name {
  static let importMCPServers = Notification.Name("importMCPServers")
  static let addMCPServer = Notification.Name("addMCPServer")
  static let giveFeedback = Notification.Name("giveFeedback")
}
