// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Foundation

@Reducer
struct StdioConfigFeature {

  @ObservableState
  struct State: Equatable {
    var command: String = ""
    var arguments = ArgumentListFeature.State(placeholder: "--arg")
    var environmentVariables = KeyValueListFeature.State(
      placeholder: KeyValueListFeature.Placeholder(key: "VAR_NAME", value: ""))
    var stdioTab: StdioTab = .arguments

    init() {}

    init(from config: StdioConfig) {
      self.command = config.command
      self.arguments = ArgumentListFeature.State(
        items: config.arguments.map {
          ArgumentListFeature.Item(value: $0.value, shouldFocus: $0.shouldFocus)
        },
        selectedId: config.selectedArgumentId,
        placeholder: "--arg"
      )
      self.environmentVariables = KeyValueListFeature.State(
        items: config.environmentVariables.map {
          KeyValueListFeature.Item(
            key: $0.name, value: $0.value, shouldFocusKey: $0.shouldFocusName)
        },
        selectedId: config.selectedEnvironmentId,
        placeholder: KeyValueListFeature.Placeholder(key: "VAR_NAME", value: "")
      )
      self.stdioTab = config.stdioTab
    }

    var asConfig: StdioConfig {
      StdioConfig(
        command: command,
        arguments: arguments.items.map {
          ArgumentItem(value: $0.value, shouldFocus: $0.shouldFocus)
        },
        selectedArgumentId: arguments.selectedId,
        environmentVariables: environmentVariables.items.map {
          EnvironmentVariableItem(name: $0.key, value: $0.value, shouldFocusName: $0.shouldFocusKey)
        },
        selectedEnvironmentId: environmentVariables.selectedId,
        stdioTab: stdioTab
      )
    }
  }

  enum Action {
    case commandChanged(String)
    case stdioTabChanged(StdioTab)
    case arguments(ArgumentListFeature.Action)
    case environmentVariables(KeyValueListFeature.Action)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.arguments, action: \.arguments) {
      ArgumentListFeature()
    }

    Scope(state: \.environmentVariables, action: \.environmentVariables) {
      KeyValueListFeature()
    }

    Reduce { state, action in
      switch action {
      case let .commandChanged(command):
        state.command = command
        return .none

      case let .stdioTabChanged(tab):
        state.stdioTab = tab
        return .none

      case .arguments, .environmentVariables:
        return .none
      }
    }
  }
}
