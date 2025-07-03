// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation

/// DXT manifest structure representing the manifest.json file in a DXT package
public struct DXTManifest: Codable, Equatable, Sendable {
  public let dxtVersion: String
  public let name: String
  public let displayName: String?
  public let version: String
  public let description: String
  public let longDescription: String?
  public let author: Author
  public let repository: Repository?
  public let homepage: String?
  public let documentation: String?
  public let support: String?
  public let icon: String?
  public let server: Server
  public let tools: [Tool]?
  public let prompts: [Prompt]?
  public let keywords: [String]?
  public let license: String?
  public let userConfig: [String: UserConfigItem]?
  public let compatibility: Compatibility?
  
  public struct Author: Codable, Equatable, Sendable {
    public let name: String
    public let email: String?
    public let url: String?
  }
  
  public struct Repository: Codable, Equatable, Sendable {
    public let type: String?
    public let url: String
  }
  
  public struct Server: Codable, Equatable, Sendable {
    public let type: ServerType
    public let entryPoint: String
    public let mcpConfig: MCPConfig
    
    public enum ServerType: String, Codable, Equatable, Sendable {
      case python
      case node
      case binary
    }
    
    public struct MCPConfig: Codable, Equatable, Sendable {
      public let command: String
      public let args: [String]?
      public let env: [String: String]?
      public let workingDirectory: String?
      
      enum CodingKeys: String, CodingKey {
        case command
        case args
        case env
        case workingDirectory = "working_directory"
      }
    }
    
    enum CodingKeys: String, CodingKey {
      case type
      case entryPoint = "entry_point"
      case mcpConfig = "mcp_config"
    }
  }
  
  public struct Tool: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
  }
  
  public struct Prompt: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let template: String?
  }
  
  public struct UserConfigItem: Codable, Equatable, Sendable {
    public let type: String
    public let title: String?
    public let description: String?
    public let defaultValue: JSONValue?
    public let sensitive: Bool?
    public let required: Bool?
    public let multiple: Bool?
    public let min: Double?
    public let max: Double?
    
    enum CodingKeys: String, CodingKey {
      case type
      case title
      case description
      case defaultValue = "default"
      case sensitive
      case required
      case multiple
      case min
      case max
    }
  }
  
  public struct Compatibility: Codable, Equatable, Sendable {
    public let claudeDesktop: String?
    public let context: String?
    public let platforms: [String]?
    public let runtimes: [String: String]?
    public let env: [String: String]?
    public let platformOverrides: [String: PlatformOverride]?
    
    public struct PlatformOverride: Codable, Equatable, Sendable {
      public let command: String?
      public let args: [String]?
      public let env: [String: String]?
    }
    
    enum CodingKeys: String, CodingKey {
      case claudeDesktop = "claude_desktop"
      case context
      case platforms
      case runtimes
      case env
      case platformOverrides = "platform_overrides"
    }
  }
  
  enum CodingKeys: String, CodingKey {
    case dxtVersion = "dxt_version"
    case name
    case displayName = "display_name"
    case version
    case description
    case longDescription = "long_description"
    case author
    case repository
    case homepage
    case documentation
    case support
    case icon
    case server
    case tools
    case prompts
    case keywords
    case license
    case userConfig = "user_config"
    case compatibility
  }
}
