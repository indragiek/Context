// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import SwiftUI

struct ResourceDetailView: View {
  let resource: Resource
  let server: MCPServer

  var body: some View {
    ResourceDetailContent(resource: resource, server: server)
  }
}

struct ResourceTemplateDetailView: View {
  let template: ResourceTemplate
  let server: MCPServer

  var body: some View {
    ResourceTemplateDetailContent(template: template, server: server)
  }
}
