// MCPServer.swift — Model Context Protocol server for VS Code integration
//
// Junco can serve as an MCP server, allowing VS Code extensions (Copilot, Claude)
// to use junco's local tools: file search, code context, on-device inference.
//
// MCP Protocol: JSON-RPC over stdio
// Spec: https://modelcontextprotocol.io
//
// This is the server skeleton. Full implementation in a future milestone.

import Foundation

/// MCP server that exposes junco's capabilities to external editors.
///
/// ## Integration with VS Code
///
/// Add to VS Code's settings.json:
/// ```json
/// {
///   "mcp.servers": {
///     "junco": {
///       "command": "junco",
///       "args": ["--mcp", "--directory", "${workspaceFolder}"]
///     }
///   }
/// }
/// ```
///
/// ## Exposed Tools
///
/// - `junco/search` — Search project files using RAG index
/// - `junco/analyze` — Analyze a file or function with on-device LLM
/// - `junco/suggest` — Get edit suggestions for a code snippet
/// - `junco/reflect` — Retrieve relevant past reflections
///
/// ## Exposed Resources
///
/// - `junco://index` — Project file index
/// - `junco://reflections` — Stored reflections for the project
/// - `junco://domain` — Detected project domain and configuration
///
public actor MCPServer {
  private let orchestrator: Orchestrator
  private var running = false

  public init(orchestrator: Orchestrator) {
    self.orchestrator = orchestrator
  }

  /// Start the MCP server, reading JSON-RPC from stdin, writing to stdout.
  public func start() async {
    running = true

    // MCP handshake: server sends capabilities
    let capabilities = MCPCapabilities(
      tools: [
        MCPTool(name: "junco/search", description: "Search project code", inputSchema: [:]),
        MCPTool(name: "junco/analyze", description: "Analyze code with on-device LLM", inputSchema: [:]),
        MCPTool(name: "junco/suggest", description: "Get edit suggestions", inputSchema: [:]),
        MCPTool(name: "junco/reflect", description: "Retrieve past reflections", inputSchema: [:])
      ],
      resources: [
        MCPResource(uri: "junco://index", name: "Project Index"),
        MCPResource(uri: "junco://domain", name: "Domain Config")
      ]
    )

    // Write initialization response
    let initResponse = """
    {"jsonrpc":"2.0","id":0,"result":{"capabilities":\(capabilities.json)}}
    """
    print(initResponse)
    fflush(stdout)

    // Main loop: read JSON-RPC requests from stdin
    while running {
      guard let line = readLine() else { break }
      // Parse and handle JSON-RPC request
      // Full implementation deferred to dedicated MCP milestone
      if line.contains("shutdown") {
        running = false
      }
    }
  }
}

// MARK: - MCP Types (minimal)

struct MCPCapabilities: Sendable {
  let tools: [MCPTool]
  let resources: [MCPResource]

  var json: String {
    let toolsJson = tools.map { "{\"name\":\"\($0.name)\",\"description\":\"\($0.description)\"}" }
    let resourcesJson = resources.map { "{\"uri\":\"\($0.uri)\",\"name\":\"\($0.name)\"}" }
    return "{\"tools\":[\(toolsJson.joined(separator: ","))],\"resources\":[\(resourcesJson.joined(separator: ","))]}"
  }
}

struct MCPTool: Sendable {
  let name: String
  let description: String
  let inputSchema: [String: String]
}

struct MCPResource: Sendable {
  let uri: String
  let name: String
}
