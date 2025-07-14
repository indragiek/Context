// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

extension View {
  func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
    if condition {
      return AnyView(transform(self))
    } else {
      return AnyView(self)
    }
  }
  
  @ViewBuilder
  func nullPlaceholder<Content: View>(
    when shouldShow: Bool,
    alignment: Alignment = .leading,
    @ViewBuilder placeholder: () -> Content
  ) -> some View {
    ZStack(alignment: alignment) {
      placeholder().opacity(shouldShow ? 1 : 0)
      self
    }
  }
}