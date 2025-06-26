## Bash commands
- swift build: Build the package
- swift test: Test the package

## Code Style
- Do not add excessive comments within function bodies. Only add comments within function bodies to highlight specific details that may not be obvious.
- For public functions, add function documentation that summarizes the behavior of the function in 1-3 sentences and document all parameters, return values, and any errors the function might throw.
- For private functions, do not write complete function documentation and just summarize what the function does in 1-2 sentences.

## Model Context Protocol
- This package contains an implementation of the Model Context Protocol (MCP), as documented here: https://modelcontextprotocol.io/specification/2025-03-26
- The TypeScript definition of the Model Context Protocol schema can be found at: https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/refs/heads/main/schema/2025-03-26/schema.ts

## Source Code
- All source code is located in Sources/ContextCore, and macro definitions are located in Sources/ContextCoreMacros
- JSONRPC.swift contains the JSON-RPC 2.0 protocol implementation. JSONRPCMacros.swift contains macro definitions that simplify defining JSON-RPC requests, responses, and notifications
- JSONValue.swift contains the definition of the JSONValue type, which implements a dynamic container for any JSON-encodable data. This is used to represent types where the schema is unknown. See Schema.swift for examples of how JSONValue is used.
- Schema.swift contains Swift definitions of all of the Model Context Protocol schema definition types. When generating code, DO NOT re-define new schema types. Use the existing types defined in Schema.swift.
- StdioTransport.swift contains an implementation of the MCP stdio transport as documented here: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#stdio
- StreamableHTTPTransport.swift contains an implementation of the MCP streamable HTTP transport as documented here: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#streamable-http. This implementation is also backward compatible with the older HTTP+SSE transport as documented here: https://modelcontextprotocol.io/specification/2024-11-05/basic/transports#http-with-sse

## Testing
- All test code is located in Tests/ContextCoreTests
- Tests/ContextCoreTests/mcp-servers contains numerous MCP server implementations written in Python. The servers are implemented using the FastMCP framework (https://github.com/jlowin/fastmcp)
- The servers are invoked using uv (https://github.com/astral-sh/uv), a standalone Python project manager. The scripts are invoked from within Swift test code by calling `uv run`. See StdioTransportTests.swift and StreamableHTTPTransportTests.swift for examples of how the Python servers are started from Swift test code.
