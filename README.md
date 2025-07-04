# Context

A beautiful, fully native macOS client for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/introduction) that empowers developers to interact with and debug their MCP servers.

![Context Hero](./images/Hero.png)

## Overview

Context is a native macOS app that makes it easy to test and debug MCP servers. It provides a visual interface to invoke tools, preview resources, and monitor logs in real-time. Built specifically for MCP server developers, it supports multiple simultaneous connections and provides the debugging visibility you need during development.

While the current feature set covers the essentials, Context is actively being developed into a comprehensive MCP debugging suite. Future releases will include more complete MCP specification support, advanced debugging tools like tracing and proxying, and an integrated chat client that can access all functionality exposed by MCP servers.

## Features

* Native macOS application built with Swift and SwiftUI
* Connect to multiple MCP servers simultaneously
* Auto-import of MCP servers from Cursor, Claude Code, Claude Desktop, Windsurf, and VS Code
* Auto-generated UI for tool invocation based on JSON Schema
* Dynamic prompt generation with template-based arguments
* Built-in resource previews with syntax highlighting and QuickLook support
* Real-time log streaming with filtering and structured log viewing
* Comprehensive MCP specification support (work in progress)
* OAuth with dynamic client registration and metadata discovery
* Support for stdio and Streamable HTTP transports (including HTTP+SSE backward compatibility)

## Screenshots

<table>
  <tr>
    <td><img src="./images/Tools.png" alt="Tools Interface" /></td>
    <td><img src="./images/Prompts.png" alt="Prompts Interface" /></td>
  </tr>
  <tr>
    <td><img src="./images/Resources.png" alt="Resources Interface" /></td>
    <td><img src="./images/Logs.png" alt="Logs Interface" /></td>
  </tr>
</table>

## MCP Feature Support

**Supported MCP Protocol Version:** [2025-03-26](https://modelcontextprotocol.io/specification/2025-03-26)

_Support for protocol version 2025-06-18 is a work-in-progress_

| Feature | Status |
|---------|--------|
| **Transports** | |
| stdio | ✅ Supported |
| Streamable HTTP | ✅ Supported |
| HTTP+SSE | ✅ Supported |
| **Authentication** | |
| OAuth 2.1 (IETF DRAFT) | ✅ Supported |
| OAuth 2.0 Auth Server Metadata | ✅ Supported |
| OAuth 2.0 Dynamic Client Registration | ✅ Supported |
| OAuth 2.0 Protected Resource Metadata | ✅ Supported |
| **Core Features** | |
| Ping | ✅ Supported |
| Prompts | ✅ Supported |
| Resources | ✅ Supported |
| Tools | ✅ Supported |
| Logging | ✅ Supported |
| **Advanced Features** | |
| Roots | ✅ Not Supported |
| Sampling | ❌ Not Supported |
| Elicitation | ❌ Not Supported |
| Completion | ❌ Not Supported |
| Pagination | ✅ Supported |

## Project Structure

- **`Context/`** - The macOS application source code
- **`ContextCore/`** - Swift library implementing the MCP client, including stdio and Streamable HTTP transports

## Installation

Download the latest release from the [GitHub Releases](https://github.com/indragiek/Context/releases) page.

**System Requirements:** macOS 15.0 or higher

## Privacy & Telemetry

Context uses Sentry for crash reporting and user feedback to help improve the application. If you prefer to disable telemetry:

- Compile the app with the `SENTRY_DISABLED` pre-processor flag
- Pre-compiled releases on GitHub have Sentry enabled by default

## Contributing

Contributions and feedback are warmly welcomed! You can:

- 🐛 File a [GitHub Issue](https://github.com/indragiek/Context/issues) for bugs or feature requests
- 💬 Send private feedback directly from the app via **"Give Feedback"**
- 🔧 Submit pull requests to improve Context

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Developer

Created by [Indragie Karunaratne](mailto:i@indragie.com)
