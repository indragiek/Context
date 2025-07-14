// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct NullValueEditor: View {
  @Binding var value: JSONValue
  
  var body: some View {
    Text("null")
      .font(.system(size: 12, design: .monospaced))
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}