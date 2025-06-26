// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftUI

struct ToggleButton<SelectionValue: Hashable>: View {
  let items: [(label: String, value: SelectionValue)]
  @Binding var selection: SelectionValue
  @State private var hoveredItem: SelectionValue?

  var body: some View {
    HStack(spacing: 4) {
      ForEach(items, id: \.value) { item in
        Button(action: {
          selection = item.value
        }) {
          Text(item.label)
            .font(.system(size: 13))
            .foregroundColor(selection == item.value ? Color.accentColor : Color.primary)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColorFor(item: item.value))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
          hoveredItem = isHovered ? item.value : nil
        }
      }
    }
    .padding(4)
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }

  private func backgroundColorFor(item: SelectionValue) -> Color {
    if selection == item {
      return Color.accentColor.opacity(0.2)
    } else if hoveredItem == item {
      return Color.primary.opacity(0.08)
    } else {
      return Color.clear
    }
  }
}

// Convenience initializer for simple cases with CaseIterable enums
extension ToggleButton
where SelectionValue: CaseIterable & RawRepresentable, SelectionValue.RawValue == String {
  init(selection: Binding<SelectionValue>) {
    self.init(
      items: SelectionValue.allCases.map { ($0.rawValue, $0) },
      selection: selection
    )
  }
}
