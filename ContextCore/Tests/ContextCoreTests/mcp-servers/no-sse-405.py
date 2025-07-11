# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "fastmcp",
# ]
# ///
import argparse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response, JSONResponse
from starlette.types import ASGIApp
from starlette.middleware import Middleware as ASGIMiddleware
from fastmcp import FastMCP


class NoSSEMiddleware(BaseHTTPMiddleware):
    """Middleware that simulates environments where SSE is not supported by rejecting GET SSE requests."""
    
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # Intercept GET requests to /mcp endpoint
        if request.method == "GET" and request.url.path == "/mcp":
            # Return 405 Method Not Allowed for GET requests (no SSE support)
            return JSONResponse(
                {"error": "Method Not Allowed", "message": "SSE streams not supported"},
                status_code=405,
                headers={"Allow": "POST, DELETE, OPTIONS"}
            )
        
        # Let other requests proceed normally
        return await call_next(request)


# Create MCP server instance
mcp = FastMCP(
    name="no-sse-405",
    version="1.0.0"
)


@mcp.tool()
def echo_tool(message: str) -> str:
    """Echo the given message."""
    return message


@mcp.resource("resource://test/greeting")
def get_greeting() -> str:
    """Get a greeting message."""
    return "Hello from MCP server without SSE support!"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MCP Server without SSE support (405 on GET)")
    parser.add_argument("--port", "-p", type=int, default=9005,
                       help="Port number to run the server on (default: 9005)")
    
    args = parser.parse_args()
    
    # Create the ASGI app with middleware
    http_middlewares = [
        ASGIMiddleware(NoSSEMiddleware)
    ]
    
    app = mcp.http_app(middleware=http_middlewares, transport="streamable-http", path="/mcp")
    
    # Run the app
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=args.port)