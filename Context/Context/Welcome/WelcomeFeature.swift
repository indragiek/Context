import ComposableArchitecture
import SwiftUI

@Reducer
struct WelcomeFeature {
  @ObservableState
  struct State: Equatable {
    var isVisible = false
  }

  enum Action {
    case importServersButtonTapped
    case addServerButtonTapped
    case addReferenceServersButtonTapped
    case dismiss
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .importServersButtonTapped:
        return .none

      case .addServerButtonTapped:
        return .none

      case .addReferenceServersButtonTapped:
        return .none

      case .dismiss:
        state.isVisible = false
        return .none
      }
    }
  }
}
