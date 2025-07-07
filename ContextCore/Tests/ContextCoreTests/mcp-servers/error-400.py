# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "fastapi",
#     "uvicorn",
# ]
# ///
import argparse
import json
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

app = FastAPI()

@app.post("/mcp")
async def handle_mcp_request(request: Request):
    """Always return HTTP 400 with a JSON-RPC error response"""
    body = await request.json()
    
    # Create a JSON-RPC error response
    error_response = {
        "jsonrpc": "2.0",
        "error": {
            "code": -32600,
            "message": "The data couldn't be read because it isn't in the correct format."
        },
        "id": body.get("id")  # Use the same ID from the request
    }
    
    return JSONResponse(
        status_code=400,
        content=error_response,
        headers={
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        }
    )

@app.get("/mcp")
async def handle_sse_request():
    """Return 400 for SSE requests with same error as POST"""
    error_response = {
        "jsonrpc": "2.0",
        "error": {
            "code": -32600,
            "message": "The data couldn't be read because it isn't in the correct format."
        },
        "id": None
    }
    
    return JSONResponse(
        status_code=400,
        content=error_response,
        headers={
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        }
    )

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Error 400 MCP Server")
    parser.add_argument("--port", "-p", type=int, default=9000,
                       help="Port number to run the server on (default: 9000)")
    
    args = parser.parse_args()
    
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=args.port)