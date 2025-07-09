// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ContextCore
import Foundation
import SharingGRDB

enum TransportType: String, Codable, QueryBindable, Equatable {
  case stdio = "stdio"
  case sse = "sse"
  case streamableHTTP = "streamable_http"
  case dxt = "dxt"
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

  @Column("working_directory_path")
  var workingDirectoryPath: String?

  @Column("auto_reload_enabled")
  var autoReloadEnabled: Bool = false

  @Column("dxt_user_config", as: DXTUserConfigurationValues?.JSONRepresentation.self)
  var dxtUserConfig: DXTUserConfigurationValues?
}

@Table("mcp_roots")
struct MCPRoot: Equatable, Identifiable {
  let id: UUID
  var name: String
  var uri: String
}

@Table("global_environment")
struct GlobalEnvironmentVariable: Equatable, Identifiable {
  let id: UUID
  var key: String
  var value: String
}
