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

from fastmcp import FastMCP, Client
from fastmcp.server.middleware import Middleware, MiddlewareContext, CallNext
import mcp.types as mt


class PingTrackingMiddleware(Middleware):
    """
    A stateful FastMCP middleware that counts the number of ping requests received.
    """
    def __init__(self):
        super().__init__()
        self.ping_count = 0
        print("PingTrackingMiddleware initialized. Ping count: 0")

    async def on_request(self, context: MiddlewareContext[mt.Request], call_next: CallNext) -> Any:
        """
        This hook is called for every incoming MCP request. We inspect the method
        to see if it's a ping.
        """
        print(f"Received MCP request: method={context.method}")
        if context.method == "ping":
            self.ping_count += 1
            print(f"Ping request received! Total pings: {self.ping_count}")
        
        # Always call the next middleware in the chain.
        return await call_next(context)

    def get_ping_count(self) -> int:
        """A helper method to retrieve the current count."""
        return self.ping_count


class CustomHeaderMiddleware(BaseHTTPMiddleware):
    """
    A Starlette-compatible ASGI middleware to inject custom HTTP headers into responses.
    """
    def __init__(self, app: ASGIApp, keep_alive_timeout: int = 5):
        super().__init__(app)
        self.keep_alive_timeout = keep_alive_timeout

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # First, we let the request go through the rest of the application
        # to get the response object.
        response = await call_next(request)
        
        # Now, we modify the headers on the outgoing response.
        # For streamable HTTP transport, check if it's a GET request with text/event-stream Accept header
        accept_header = request.headers.get("accept", "")
        print(f"Request path: {request.url.path}, method: {request.method}, accept: {accept_header}")
        
        # Check content type of response to determine if it's an SSE stream
        content_type = response.headers.get("content-type", "")
        if "text/event-stream" in content_type:
            response.headers["Connection"] = "Keep-Alive"
            response.headers["Keep-Alive"] = f"timeout={self.keep_alive_timeout}, max=1000"
            print(f"Injected Keep-Alive headers into SSE response for {request.url.path} (content-type: {content_type})")
        
        return response


# Create global ping tracker
ping_tracker = PingTrackingMiddleware()

def create_server(keep_alive_timeout: int = 5):
    # Create the FastMCP server instance
    server = FastMCP(
        name="Echo",
        instructions="An echo server with Keep-Alive headers for testing."
    )

    # Add the FastMCP middleware to the server
    server.add_middleware(ping_tracker)

    @server.resource("echo://status", name="EchoStatus", description="Returns the service status")
    def echo_status() -> str:
        """Returns the service status"""
        return "ok"

    @server.resource("echo://{message}")
    def echo_resource(message: str, name="EchoMessage", description="Echo a message as a resource") -> str:
        """Echo a message as a resource"""
        return f"Resource echo: {message}"

    @server.tool()
    def echo_tool(message: str) -> str:
        """Echo a message as a tool"""
        return f"Tool echo: {message}"

    @server.tool()
    def get_ping_count() -> int:
        """Returns the number of times the server has been pinged."""
        return ping_tracker.get_ping_count()

    @server.tool()
    def reset_ping_count() -> int:
        """Resets the ping count and returns the count before reset."""
        count = ping_tracker.get_ping_count()
        ping_tracker.ping_count = 0
        return count

    @server.prompt()
    def echo_prompt(message: str) -> str:
        """Create an echo prompt"""
        return f"Please process this message: {message}"
    
    return server, keep_alive_timeout


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Echo MCP Server with Keep-Alive")
    parser.add_argument("--port", "-p", type=int, default=9000,
                       help="Port number to run the server on (default: 9000)")
    parser.add_argument("--keep-alive-timeout", "-t", type=int, default=5,
                       help="Keep-Alive timeout in seconds (default: 5)")
    parser.add_argument("--transport", "-T", type=str, default="streamable-http",
                       choices=["streamable-http", "sse"],
                       help="Transport type to use (default: streamable-http)")

    args = parser.parse_args()
    
    server, keep_alive_timeout = create_server(keep_alive_timeout=args.keep_alive_timeout)
    
    # Define the Starlette middleware
    http_middlewares = [
        ASGIMiddleware(CustomHeaderMiddleware, keep_alive_timeout=keep_alive_timeout)
    ]
    
    # Create the ASGI app with the HTTP-level middleware
    if args.transport == "streamable-http":
        app = server.http_app(middleware=http_middlewares, transport="streamable-http", path="/mcp")
    else:
        app = server.http_app(middleware=http_middlewares, transport="sse")
    
    # Run the app
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=args.port)