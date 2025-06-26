# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "fastmcp",
# ]
# ///
import argparse
from fastmcp import FastMCP

mcp = FastMCP("Echo")

@mcp.resource("echo://status", name="EchoStatus", description="Returns the service status")
def echo_status() -> str:
    """Returns the service status"""
    return "ok"


@mcp.resource("echo://{message}")
def echo_resource(message: str, name="EchoMessage", description="Echo a message as a resource") -> str:
    """Echo a message as a resource"""
    return f"Resource echo: {message}"


@mcp.tool()
def echo_tool(message: str) -> str:
    """Echo a message as a tool"""
    return f"Tool echo: {message}"


@mcp.prompt()
def echo_prompt(message: str) -> str:
    """Create an echo prompt"""
    return f"Please process this message: {message}"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Echo MCP Server")
    parser.add_argument("--port", "-p", type=int, default=9000,
                       help="Port number to run the server on (default: 9000)")

    args = parser.parse_args()

    mcp.run(transport="streamable-http", host="127.0.0.1", port=args.port, path="/mcp")

