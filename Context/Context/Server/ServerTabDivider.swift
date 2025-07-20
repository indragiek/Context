// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ServerTabDivider: View {
  let isHidden: Bool

  var body: some View {
    Rectangle()
      .fill(Color(NSColor.separatorColor))
      .frame(width: 1)
      .opacity(isHidden ? 0 : 1)
  }
}
