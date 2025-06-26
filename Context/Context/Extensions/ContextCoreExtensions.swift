// Copyright © 2025 Indragie Karunaratne. All rights reserved.

public import ContextCore

// MARK: - Identifiable Conformances

extension Prompt: @retroactive Identifiable {
  public var id: String { name }
}

extension Tool: @retroactive Identifiable {
  public var id: String { name }
}

extension Resource: @retroactive Identifiable {
  public var id: String { uri }
}

extension ResourceTemplate: @retroactive Identifiable {
  public var id: String { uriTemplate }
}
