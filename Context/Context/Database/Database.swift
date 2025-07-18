import Foundation
import SharingGRDB
import os

private let logger = Logger(subsystem: "com.indragie.Context", category: "Database")

func appDatabase() throws -> any DatabaseWriter {
  let databaseURL = try FileManager.default
    .url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appendingPathComponent("Context", isDirectory: true)
  try FileManager.default.createDirectory(at: databaseURL, withIntermediateDirectories: true)
  let databasePath = databaseURL.appendingPathComponent("context.db").path
  logger.info("Database path: \(databasePath)")

  var configuration = Configuration()
  let configureDatabase: @Sendable (Database) -> Void = { db in
    // Previous versions of the app did not provide an implementation of the uuid()
    // function, which does not exist in SQLite.
    let uuid = DatabaseFunction("uuid", argumentCount: 0, pure: true) { _ in
      UUID().uuidString
    }
    db.add(function: uuid)
  }
  #if DEBUG
    configuration.prepareDatabase { db in
      db.trace { logger.debug("SQL: \($0)") }
      configureDatabase(db)
    }
  #else
    configuration.prepareDatabase { db in
      configureDatabase(db)
    }
  #endif

  let dbWriter = try DatabasePool(path: databasePath, configuration: configuration)
  var migrator = DatabaseMigrator()
  migrator.registerMigration("Create 'mcp_servers' table") { db in
    try #sql(
      """
      CREATE TABLE "mcp_servers" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "name" TEXT NOT NULL,
        "transport" TEXT NOT NULL,
        "command" TEXT,
        "args" TEXT,
        "url" TEXT,
        "environment" TEXT,
        "headers" TEXT,
        "watched_paths" TEXT,
        "working_directory_path" TEXT,
        "auto_reload_enabled" INTEGER NOT NULL
      )
      """
    )
    .execute(db)
  }

  migrator.registerMigration("Add 'dxt_user_config' column to 'mcp_servers'") { db in
    try db.alter(table: "mcp_servers") { t in
      t.add(column: "dxt_user_config", .text)
    }
  }

  migrator.registerMigration("Create 'mcp_roots' table") { db in
    try #sql(
      """
      CREATE TABLE "mcp_roots" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "name" TEXT NOT NULL,
        "uri" TEXT NOT NULL
      )
      """
    )
    .execute(db)
  }

  migrator.registerMigration("Create 'global_environment' table") { db in
    try #sql(
      """
      CREATE TABLE "global_environment" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "key" TEXT NOT NULL,
        "value" TEXT NOT NULL
      )
      """
    )
    .execute(db)
  }

  migrator.registerMigration("Add 'mcp_metadata_url' column to 'mcp_servers'") { db in
    try db.alter(table: "mcp_servers") { t in
      t.add(column: "mcp_metadata_url", .text)
    }
  }

  try migrator.migrate(dbWriter)
  return dbWriter
}
