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
      db.trace { print("SQL: \($0)") }
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

  try migrator.migrate(dbWriter)
  return dbWriter
}
