// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct TypeSelector: View {
  @Binding var selectedType: String
  
  private let jsonTypes = [
    ("string", "String"),
    ("number", "Number"),
    ("integer", "Integer"),
    ("boolean", "Boolean"),
    ("array", "Array"),
    ("object", "Object"),
    ("null", "Null")
  ]
  
  var body: some View {
    Menu {
      ForEach(jsonTypes, id: \.0) { type, label in
        Button(action: {
          selectedType = type
        }) {
          HStack {
            Text(label)
            if selectedType == type {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      Text(jsonTypes.first(where: { $0.0 == selectedType })?.1 ?? "String")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help("Select the type for this property")
  }
}