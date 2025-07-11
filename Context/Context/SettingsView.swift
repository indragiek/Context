import ComposableArchitecture
import Sparkle
import SwiftUI

struct SettingsView: View {
  private let updater: SPUUpdater
  private let rootsStore: StoreOf<RootsFeature>
  private let globalEnvironmentStore: StoreOf<GlobalEnvironmentFeature>

  init(updater: SPUUpdater) {
    self.updater = updater
    self.rootsStore = Store(initialState: RootsFeature.State()) {
      RootsFeature()
    }
    self.globalEnvironmentStore = Store(initialState: GlobalEnvironmentFeature.State()) {
      GlobalEnvironmentFeature()
    }
  }

  var body: some View {
    TabView {
      GlobalEnvironmentView(store: globalEnvironmentStore)
        .tabItem {
          Label("Environment", systemImage: "curlybraces")
        }
        .tag(0)
      RootsView(store: rootsStore)
        .tabItem {
          Label("Roots", systemImage: "folder")
        }
        .tag(1)
      UpdaterSettingsView(updater: updater)
        .tabItem {
          Label("Updates", systemImage: "arrow.down.circle")
        }
        .tag(2)
    }
    .frame(width: 600, height: 450)
  }
}

struct UpdaterSettingsView: View {
  @State private var updaterViewModel: UpdaterViewModel

  init(updater: SPUUpdater) {
    self._updaterViewModel = State(wrappedValue: UpdaterViewModel(updater: updater))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Toggle(
        "Automatically check for updates", isOn: $updaterViewModel.automaticallyChecksForUpdates
      )
      .help("When enabled, Context will periodically check for updates in the background")

      Toggle(
        "Automatically download updates", isOn: $updaterViewModel.automaticallyDownloadsUpdates
      )
      .disabled(!updaterViewModel.automaticallyChecksForUpdates)
      .help("When enabled, updates will be downloaded automatically when available")

      HStack {
        Text("Check for updates:")
        Picker("", selection: $updaterViewModel.updateCheckInterval) {
          Text("Daily").tag(86400.0)
          Text("Weekly").tag(604800.0)
          Text("Monthly").tag(2592000.0)
        }
        .pickerStyle(.menu)
        .fixedSize()
        Spacer()
      }
      .disabled(!updaterViewModel.automaticallyChecksForUpdates)

      Spacer()
    }
    .padding(20)
  }
}

@Observable
class UpdaterViewModel {
  private let updater: SPUUpdater

  var automaticallyChecksForUpdates: Bool {
    didSet {
      updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  var automaticallyDownloadsUpdates: Bool {
    didSet {
      updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
    }
  }

  var updateCheckInterval: TimeInterval {
    didSet {
      updater.updateCheckInterval = updateCheckInterval
    }
  }

  init(updater: SPUUpdater) {
    self.updater = updater
    self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    self.updateCheckInterval = updater.updateCheckInterval
  }
}

#Preview {
  SettingsView(
    updater: SPUUpdater(
      hostBundle: Bundle.main, applicationBundle: Bundle.main,
      userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil), delegate: nil))
}
