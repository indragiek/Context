// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import Foundation

@Reducer
struct HTTPConfigFeature {

  @ObservableState
  struct State: Equatable {
    var url: String = ""
    var headers = KeyValueListFeature.State(
      placeholder: KeyValueListFeature.Placeholder(key: "Authorization", value: ""))
    var urlAutoUpdate: Bool = true

    init() {}

    init(from config: HTTPConfig) {
      self.url = config.url
      self.headers = KeyValueListFeature.State(
        items: config.headers.map {
          KeyValueListFeature.Item(key: $0.key, value: $0.value, shouldFocusKey: $0.shouldFocusKey)
        },
        selectedId: config.selectedHeaderId,
        placeholder: KeyValueListFeature.Placeholder(key: "Authorization", value: "")
      )
    }

    var asConfig: HTTPConfig {
      HTTPConfig(
        url: url,
        headers: headers.items.map {
          HeaderItem(key: $0.key, value: $0.value, shouldFocusKey: $0.shouldFocusKey)
        },
        selectedHeaderId: headers.selectedId
      )
    }
  }

  enum Action {
    case urlChanged(String)
    case setURLAutoUpdate(Bool)
    case headers(KeyValueListFeature.Action)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.headers, action: \.headers) {
      KeyValueListFeature()
    }

    Reduce { state, action in
      switch action {
      case let .urlChanged(url):
        state.url = url
        return .none

      case let .setURLAutoUpdate(enabled):
        state.urlAutoUpdate = enabled
        return .none

      case .headers:
        return .none
      }
    }
  }
}
