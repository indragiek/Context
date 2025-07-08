// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum JSONRPCRequestMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard declaration.as(StructDeclSyntax.self) != nil else {
      throw MacroError("@JSONRPCRequest can only be applied to struct declarations")
    }

    guard let args = node.arguments?.as(LabeledExprListSyntax.self),
      args.count >= 2
    else {
      throw MacroError("@JSONRPCRequest requires 'method' and 'responseType' arguments")
    }

    guard let methodArg = args.first(where: { $0.label?.text == "method" }),
      let methodStringExpr = methodArg.expression.as(StringLiteralExprSyntax.self)
    else {
      throw MacroError("'method' argument must be a string literal")
    }

    guard let responseTypeArg = args.first(where: { $0.label?.text == "responseType" }) else {
      throw MacroError("'responseType' argument was not specified'")
    }

    let responseTypeName: String
    if let memberAccessExpr = responseTypeArg.expression.as(MemberAccessExprSyntax.self),
      let baseExpr = memberAccessExpr.base,
      let identifierExpr = baseExpr.as(DeclReferenceExprSyntax.self)
    {
      responseTypeName = identifierExpr.baseName.text
    } else if let identifierExpr = responseTypeArg.expression.as(DeclReferenceExprSyntax.self) {
      responseTypeName = identifierExpr.baseName.text
    } else {
      throw MacroError("unsupported type expression for 'responseType'")
    }

    let properties: [DeclSyntax] = [
      "public let jsonrpc: String",
      "public let method: String",
      "public let params: Params?",
      "public let id: JSONRPCRequestID",
      """
      public let responseDecoder: ResponseDecoder = { decoder, data in
          return try decoder.decode(\(raw: responseTypeName).self, from: data)
      }
      """,
    ]

    let generatedParamsInit = generateParamsInitCode(
      declaration: declaration, paramStructName: "Params")
    let initializerSyntax: DeclSyntax

    if generatedParamsInit.initDecl.isEmpty {
      initializerSyntax = """
        public init(id: JSONRPCRequestID) {
            self.jsonrpc = "2.0"
            self.method = \(raw: methodStringExpr.description)
            self.params = nil
            self.id = id
        }
        """
    } else {
      initializerSyntax = """
        public init(id: JSONRPCRequestID, \(raw: generatedParamsInit.initDecl)) {
            self.jsonrpc = "2.0"
            self.method = \(raw: methodStringExpr.description)
            self.params = \(raw: generatedParamsInit.initCode)
            self.id = id
        }
        """
    }

    let codingKeysSyntax: DeclSyntax = """
      enum CodingKeys: String, CodingKey {
          case jsonrpc
          case method
          case params
          case id
      }
      """

    let responseTypeSyntax: DeclSyntax = """
          public typealias Response = \(raw: responseTypeName)
      """

    let typeName = declaration.as(StructDeclSyntax.self)?.name.text ?? "Type"
    
    // Generate debug description that handles optional params
    let paramsMembers = extractStructMembers(declaration: declaration, structName: "Params")
    let debugDescriptionSyntax: DeclSyntax
    
    if paramsMembers.isEmpty {
      // Empty params struct - params will always be nil when initialized without args
      debugDescriptionSyntax = """
        public var debugDescription: String {
            \"\"\"
            \(raw: typeName) {
                method=\"\\(method)\",
                id=\\(String(reflecting: id)),
                params=nil
            }
            \"\"\"
        }
        """
    } else {
      // Non-empty params struct - show the fields
      let fieldLinesCode = paramsMembers.map {
        "\($0.name)=\\(String(reflecting: self.params!.\($0.name)))"
      }.joined(separator: ",\n                ")
      
      debugDescriptionSyntax = """
        public var debugDescription: String {
            if let params = self.params {
                return \"\"\"
                \(raw: typeName) {
                    method=\"\\(method)\",
                    id=\\(String(reflecting: id)),
                    params={
                        \(raw: fieldLinesCode.replacingOccurrences(of: "self.params!", with: "params"))
                    }
                }
                \"\"\"
            } else {
                return \"\"\"
                \(raw: typeName) {
                    method=\"\\(method)\",
                    id=\\(String(reflecting: id)),
                    params=nil
                }
                \"\"\"
            }
        }
        """
    }

    let descriptionSyntax = generateDescription(
      typeName: typeName,
      dataFieldName: "params",
      fields: ["method=\"\\(method)\"", "id=\\(String(reflecting: id))"]
    )

    return properties + [
      initializerSyntax, codingKeysSyntax, responseTypeSyntax, debugDescriptionSyntax,
      descriptionSyntax,
    ]
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let extensionDecl = try ExtensionDeclSyntax(
      "extension \(type): JSONRPCRequest, Codable, CustomDebugStringConvertible, CustomStringConvertible { }"
    )
    return [extensionDecl]
  }
}

public enum JSONRPCNotificationMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard declaration.as(StructDeclSyntax.self) != nil else {
      throw MacroError("@JSONRPCNotification can only be applied to struct declarations")
    }

    guard let args = node.arguments?.as(LabeledExprListSyntax.self),
      args.count >= 1
    else {
      throw MacroError("@JSONRPCNotification requires a 'method' argument")
    }

    guard let methodArg = args.first(where: { $0.label?.text == "method" }),
      let methodStringExpr = methodArg.expression.as(StringLiteralExprSyntax.self)
    else {
      throw MacroError("'method' argument must be a string literal")
    }

    let properties: [DeclSyntax] = [
      "public let jsonrpc: String",
      "public let method: String",
      "public let params: Params?",
    ]

    let generatedParamsInit = generateParamsInitCode(
      declaration: declaration, paramStructName: "Params")
    let initializerSyntax: DeclSyntax
    
    if generatedParamsInit.initDecl.isEmpty {
      initializerSyntax = """
        public init() {
            self.jsonrpc = "2.0"
            self.method = \(raw: methodStringExpr.description)
            self.params = nil
        }
        """
    } else {
      initializerSyntax = """
        public init(\(raw: generatedParamsInit.initDecl)) {
            self.jsonrpc = "2.0"
            self.method = \(raw: methodStringExpr.description)
            self.params = \(raw: generatedParamsInit.initCode)
        }
        """
    }

    let codingKeysSyntax: DeclSyntax = """
      enum CodingKeys: String, CodingKey {
          case jsonrpc
          case method
          case params
      }
      """

    let typeName = declaration.as(StructDeclSyntax.self)?.name.text ?? "Type"
    
    // Generate debug description that handles optional params
    let paramsMembers = extractStructMembers(declaration: declaration, structName: "Params")
    let debugDescriptionSyntax: DeclSyntax
    
    if paramsMembers.isEmpty {
      // Empty params struct - params will always be nil when initialized without args
      debugDescriptionSyntax = """
        public var debugDescription: String {
            \"\"\"
            \(raw: typeName) {
                method=\"\\(method)\",
                params=nil
            }
            \"\"\"
        }
        """
    } else {
      // Non-empty params struct - show the fields
      let fieldLinesCode = paramsMembers.map {
        "\($0.name)=\\(String(reflecting: self.params!.\($0.name)))"
      }.joined(separator: ",\n                ")
      
      debugDescriptionSyntax = """
        public var debugDescription: String {
            if let params = self.params {
                return \"\"\"
                \(raw: typeName) {
                    method=\"\\(method)\",
                    params={
                        \(raw: fieldLinesCode.replacingOccurrences(of: "self.params!", with: "params"))
                    }
                }
                \"\"\"
            } else {
                return \"\"\"
                \(raw: typeName) {
                    method=\"\\(method)\",
                    params=nil
                }
                \"\"\"
            }
        }
        """
    }

    let descriptionSyntax = generateDescription(
      typeName: typeName,
      dataFieldName: "params",
      fields: ["method=\"\\(method)\""]
    )

    return properties + [
      initializerSyntax, codingKeysSyntax, debugDescriptionSyntax, descriptionSyntax,
    ]
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let extensionDecl = try ExtensionDeclSyntax(
      "extension \(type): JSONRPCNotification, Codable, CustomDebugStringConvertible, CustomStringConvertible { }"
    )
    return [extensionDecl]
  }
}

public enum JSONRPCResponseMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard declaration.as(StructDeclSyntax.self) != nil else {
      throw MacroError("@JSONRPCResponse can only be applied to struct declarations")
    }

    let properties: [DeclSyntax] = [
      "public let jsonrpc: String",
      "public let result: Result",
      "public let id: JSONRPCRequestID",
    ]

    let generatedResultInit = generateParamsInitCode(
      declaration: declaration, paramStructName: "Result")
    let initializerSyntax: DeclSyntax

    if generatedResultInit.initDecl.isEmpty {
      initializerSyntax = """
        public init(id: JSONRPCRequestID) {
            self.jsonrpc = "2.0"
            self.result = \(raw: generatedResultInit.initCode)
            self.id = id
        }
        """
    } else {
      initializerSyntax = """
        public init(id: JSONRPCRequestID, \(raw: generatedResultInit.initDecl)) {
            self.jsonrpc = "2.0"
            self.result = \(raw: generatedResultInit.initCode)
            self.id = id
        }
        """
    }

    let codingKeysSyntax: DeclSyntax = """
      enum CodingKeys: String, CodingKey {
          case jsonrpc
          case result
          case id
      }
      """

    let typeName = declaration.as(StructDeclSyntax.self)?.name.text ?? "Type"
    let debugDescriptionSyntax = generateDebugDescription(
      declaration: declaration,
      typeName: typeName,
      dataStructName: "Result",
      dataFieldName: "result",
      fields: ["id=\\(String(reflecting: id))"]
    )

    let descriptionSyntax = generateDescription(
      typeName: typeName,
      dataFieldName: "result",
      fields: ["id=\\(String(reflecting: id))"]
    )

    return properties + [
      initializerSyntax, codingKeysSyntax, debugDescriptionSyntax, descriptionSyntax,
    ]
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let extensionDecl = try ExtensionDeclSyntax(
      "extension \(type): JSONRPCResponse, Codable, CustomDebugStringConvertible, CustomStringConvertible { }"
    )
    return [extensionDecl]
  }
}

private func extractStructMembers(declaration: some DeclGroupSyntax, structName: String) -> [(
  name: String, type: String
)] {
  var members: [(name: String, type: String)] = []

  for member in declaration.memberBlock.members {
    if let structDecl = member.decl.as(StructDeclSyntax.self),
      structDecl.name.text == structName
    {
      for structMember in structDecl.memberBlock.members {
        if let varDecl = structMember.decl.as(VariableDeclSyntax.self),
          varDecl.bindingSpecifier.text == "let" || varDecl.bindingSpecifier.text == "var"
        {
          for binding in varDecl.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type
            {
              members.append(
                (name: identifier.identifier.text, type: type.description))
            }
          }
        }
      }
    }
  }

  return members
}

private struct GeneratedParamsInit {
  let initDecl: String
  let initCode: String
}

private func generateParamsInitCode(declaration: some DeclGroupSyntax, paramStructName: String)
  -> GeneratedParamsInit
{
  let paramsMembers = extractStructMembers(declaration: declaration, structName: paramStructName)

  var initDecl = ""
  var initCode = ""

  if paramsMembers.isEmpty {
    initDecl = ""
    initCode = "\(paramStructName)()"
  } else {
    initDecl = paramsMembers.map {
      "\($0.name): \($0.type)"
    }.joined(separator: ", ")

    let paramsArgs = paramsMembers.map {
      "\($0.name): \($0.name)"
    }.joined(separator: ", ")

    initCode = "\(paramStructName)(\(paramsArgs))"
  }
  return GeneratedParamsInit(initDecl: initDecl, initCode: initCode)
}

private func generateDescription(
  typeName: String,
  dataFieldName: String,
  fields: [String]
) -> DeclSyntax {
  var fieldsString = ""
  if !fields.isEmpty {
    fieldsString = fields.joined(separator: ",\n        ")
  }

  return """
    public var description: String {
        \"\"\"
        \(raw: typeName) {
            \(raw: fieldsString),
            \(raw: dataFieldName)=...
        }
        \"\"\"
    }
    """
}

private func generateDebugDescription(
  declaration: some DeclGroupSyntax,
  typeName: String,
  dataStructName: String,
  dataFieldName: String,
  fields: [String]
) -> DeclSyntax {
  let structMembers = extractStructMembers(declaration: declaration, structName: dataStructName)

  var fieldLinesCode = ""

  if !structMembers.isEmpty {
    fieldLinesCode = structMembers.map {
      "\($0.name)=\\(String(reflecting: self.\(dataFieldName).\($0.name)))"
    }.joined(separator: ",\n            ")
  }

  var fieldsString = ""
  if !fields.isEmpty {
    fieldsString = fields.joined(separator: ",\n        ")
  }

  return """
    public var debugDescription: String {
        \"\"\"
        \(raw: typeName) {
            \(raw: fieldsString),
            \(raw: dataFieldName)={
                \(raw: fieldLinesCode)
            }
        }
        \"\"\"
    }
    """
}

@main
struct ContextCorePlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    JSONRPCRequestMacro.self,
    JSONRPCNotificationMacro.self,
    JSONRPCResponseMacro.self,
  ]
}
