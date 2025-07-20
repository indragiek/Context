// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ServerTabSwitcher: View {
  let selectedTab: ServerTab
  let onTabSelected: (ServerTab) -> Void

  var body: some View {
    HStack(spacing: 0) {
      ForEach(ServerTab.allCases, id: \.self) { tab in
        ServerTabButton(
          tab: tab,
          isSelected: selectedTab == tab,
          action: { onTabSelected(tab) }
        )

        if tab != ServerTab.allCases.last {
          ServerTabDivider(
            isHidden: shouldHideDivider(for: tab)
          )
        }
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color(NSColor.controlBackgroundColor))
        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func shouldHideDivider(for tab: ServerTab) -> Bool {
    guard let tabIndex = ServerTab.allCases.firstIndex(of: tab) else { return false }
    let nextIndex = tabIndex + 1
    guard nextIndex < ServerTab.allCases.count else { return false }

    return selectedTab == tab || selectedTab == ServerTab.allCases[nextIndex]
  }
}
