# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "fastmcp",
# ]
# ///
from fastmcp import FastMCP, Context

mcp = FastMCP("Echo")

@mcp.tool()
async def echo_tool(message: str, ctx: Context) -> str:
    """Echo a message as a tool"""
    await ctx.info(f"Running the echo tool")
    return f"Tool echo: {message}"

if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="127.0.0.1", port=9000, path="/mcp")
