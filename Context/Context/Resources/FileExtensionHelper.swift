// Copyright © 2025 Indragie Karunaratne. All rights reserved.

enum FileExtensionHelper {
  static func fileExtension(for mimeType: String?) -> String {
    guard let mimeType = mimeType else { return "" }

    switch mimeType {
    // Text formats
    case "text/plain": return ".txt"
    case "text/html": return ".html"
    case "text/css": return ".css"
    case "text/javascript", "application/javascript": return ".js"
    case "text/typescript": return ".ts"
    case "text/markdown": return ".md"
    case "text/csv": return ".csv"
    case "text/xml": return ".xml"
    case "text/yaml", "application/x-yaml": return ".yaml"

    // Application formats
    case "application/json": return ".json"
    case "application/xml": return ".xml"
    case "application/pdf": return ".pdf"
    case "application/zip": return ".zip"
    case "application/x-ndjson": return ".ndjson"

    // Images
    case "image/png": return ".png"
    case "image/jpeg", "image/jpg": return ".jpg"
    case "image/gif": return ".gif"
    case "image/svg+xml": return ".svg"
    case "image/webp": return ".webp"
    case "image/bmp": return ".bmp"
    case "image/tiff": return ".tiff"
    case "image/x-icon": return ".ico"

    // Videos
    case "video/mp4": return ".mp4"
    case "video/quicktime": return ".mov"
    case "video/x-msvideo": return ".avi"
    case "video/webm": return ".webm"
    case "video/mpeg": return ".mpeg"
    case "video/ogg": return ".ogv"

    // Audio
    case "audio/mpeg", "audio/mp3": return ".mp3"
    case "audio/wav", "audio/x-wav": return ".wav"
    case "audio/ogg": return ".ogg"
    case "audio/aac": return ".aac"
    case "audio/flac": return ".flac"
    case "audio/webm": return ".weba"
    case "audio/midi", "audio/x-midi": return ".midi"

    // Programming languages
    case "text/x-python", "application/x-python-code": return ".py"
    case "text/x-java-source": return ".java"
    case "text/x-c": return ".c"
    case "text/x-c++": return ".cpp"
    case "text/x-csharp": return ".cs"
    case "text/x-go": return ".go"
    case "text/x-rust": return ".rs"
    case "text/x-swift": return ".swift"
    case "text/x-ruby": return ".rb"
    case "text/x-php": return ".php"

    default:
      // Try to infer from MIME type structure
      if mimeType.starts(with: "text/") {
        return ".txt"
      }
      return ""
    }
  }
}
