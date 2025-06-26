// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import SharingGRDB

enum TransportType: String, Codable, QueryBindable, Equatable {
  case stdio = "stdio"
  case sse = "sse"
  case streamableHTTP = "streamable_http"
}

@Table("mcp_servers")
struct MCPServer: Equatable, Identifiable {
  let id: UUID
  var name: String
  var transport: TransportType
  var command: String?
  var url: String?

  @Column(as: [String]?.JSONRepresentation.self)
  var args: [String]?

  @Column(as: [String: String]?.JSONRepresentation.self)
  var environment: [String: String]?

  @Column(as: [String: String]?.JSONRepresentation.self)
  var headers: [String: String]?
  
  @Column("watched_paths", as: [String]?.JSONRepresentation.self)
  var watchedPaths: [String]?
}
