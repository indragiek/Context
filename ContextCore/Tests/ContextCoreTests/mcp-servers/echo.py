# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "mcp[cli]",
# ]
# ///
from mcp.server.fastmcp import FastMCP
import sys

mcp = FastMCP("Echo")

@mcp.resource("echo://{message}")
def echo_resource(message: str) -> str:
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
    print("running mcp server", file=sys.stderr)
    sys.stderr.flush()
    mcp.run()