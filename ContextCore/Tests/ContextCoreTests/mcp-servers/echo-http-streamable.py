# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "fastmcp",
# ]
# ///
import argparse
from typing import Any
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response
from starlette.types import ASGIApp
from starlette.middleware import Middleware as ASGIMiddleware

from fastmcp import FastMCP


class CustomHeaderMiddleware(BaseHTTPMiddleware):
    """
    A Starlette-compatible ASGI middleware to inject custom HTTP headers into responses.
    """
    def __init__(self, app: ASGIApp, keep_alive_timeout: int = None):
        super().__init__(app)
        self.keep_alive_timeout = keep_alive_timeout

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # First, we let the request go through the rest of the application
        # to get the response object.
        response = await call_next(request)
        
        # Only add Keep-Alive headers if a timeout was specified
        if self.keep_alive_timeout is not None:
            # Now, we modify the headers on the outgoing response.
            # Check content type of response to add Keep-Alive headers
            content_type = response.headers.get("content-type", "")
            if "text/event-stream" in content_type or "application/json" in content_type:
                response.headers["Connection"] = "Keep-Alive"
                response.headers["Keep-Alive"] = f"timeout={self.keep_alive_timeout}, max=1000"
        
        return response


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
    parser.add_argument("--keep-alive-timeout", "-t", type=int, default=None,
                       help="Keep-Alive timeout in seconds (omit to disable Keep-Alive headers)")

    args = parser.parse_args()
    
    # Define the Starlette middleware
    http_middlewares = [
        ASGIMiddleware(CustomHeaderMiddleware, keep_alive_timeout=args.keep_alive_timeout)
    ]
    
    # Create the ASGI app with the HTTP-level middleware
    app = mcp.http_app(middleware=http_middlewares, transport="streamable-http", path="/mcp")
    
    # Run the app
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=args.port)

