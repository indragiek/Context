// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// Returns the user's real home directory URL outside the macOS app sandbox container.
///
/// When an app runs in the macOS sandbox, `FileManager.default.homeDirectoryForCurrentUser`
/// returns a path within the app's sandbox container (e.g., ~/Library/Containers/com.example.app/Data/).
/// This is problematic when trying to access user configuration files that exist in the real home
/// directory (e.g., ~/.vscode/settings.json, ~/.cursor/mcp.json, etc.).
///
/// This function uses the POSIX `getpwuid` function to retrieve the actual home directory path
/// from the system's password database, which gives us the real home directory path outside
/// the sandbox container. This allows the app to properly locate user configuration files
/// when the user explicitly grants access to their home folder through the file picker.
///
/// - Returns: The user's real home directory URL, or nil if it cannot be determined.
func getUserHomeDirectoryURLFromPasswd() -> URL? {
  let uid = getuid()
  guard let passwd = getpwuid(uid) else {
    return nil
  }

  let homeDirectory = String(cString: passwd.pointee.pw_dir)
  return URL(fileURLWithPath: homeDirectory)
}
