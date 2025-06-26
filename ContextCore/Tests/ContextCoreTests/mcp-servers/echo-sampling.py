# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "fastmcp",
# ]
# ///
from fastmcp import FastMCP, Context
import sys

mcp = FastMCP("Echo Sampling")

@mcp.tool()
async def echo_with_sampling(message: str, ctx: Context) -> str:
    """Echo a message and ask the client to generate a response"""
    # Request sampling from the client
    sampling_result = await ctx.sample(
        f"Please provide a creative response to this message: {message}"
    )
    return f"Original: {message}\nSampled response: {sampling_result.text}"

@mcp.tool()
def echo_without_sampling(message: str) -> str:
    """Echo a message without sampling"""
    return f"Simple echo: {message}"

if __name__ == "__main__":
    print("running mcp sampling server", file=sys.stderr)
    mcp.run()
