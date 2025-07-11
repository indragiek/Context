## General

- Context is an app that gives developers the ability to browse and make requests to MCP (Model Context Protocol) servers.
- The app depends on the ContextCore library, which implements the MCP client and transports. The ContextCore library source code is contained within this repository.
- The app is primarily built using SwiftUI, using AppKit as necessary using NSViewRepresentable.
- Aim to build all functionality using SwiftUI unless there is a feature that is only supported in AppKit.
- Design UI in a way that is idiomatic for the macOS platform and follows Apple Human Interface Guidelines.
- Use SF Symbols for iconography.
- Use the most modern macOS APIs. Since there is no backward compatibility constraint, this app can target the latest macOS version with the newest APIs.
- Use the most modern Swift language features and conventions. Target Swift 6 and use Swift concurrency (async/await, actors) and Swift macros where applicable.
- The app uses TCA (The Composable Architecture) for state management. The documentation for TCA can be found here: https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/.
- The app also uses the Dependencies library for dependency management, which integrates with TCA. The documentation for the Dependencies library can be found here: https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/

## Code Style

- Do not add excessive comments within function bodies. Only add comments within function bodies to highlight specific details that may not be obvious.
- Use 2 spaces for indentation
- Run `swift format -i <path>` to format the code in place

## MCP Servers

- Use the XcodeBuildMCP server to build and run the macOS application
- Before launching the app, kill the app if it's already running using the command "killall Context || true"
- NEVER use the stop_mac_app tool from XcodeBuildMCP, always use the killall command
- Use the build_run_mac_proj tool from XcodeBuildMCP to build and run the Mac app
