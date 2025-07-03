import Foundation
import SharingGRDB

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
  print("Database path: \(databasePath)")

  var configuration = Configuration()
  #if DEBUG
    configuration.prepareDatabase { db in
      db.trace { print("SQL: \($0)") }
    }
  #else
    configuration.prepareDatabase { _ in }
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

  try migrator.migrate(dbWriter)
  return dbWriter
}
