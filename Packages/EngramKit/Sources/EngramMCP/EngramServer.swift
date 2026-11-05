import EngramKit
import Foundation
import MCP

/// Serves Engram's tools over stdin/stdout until Claude closes the connection.
public enum EngramServer {
  public static func run(database: AppDatabase, version: String) async throws {
    let server = Server(
      name: "engram", version: version, title: "Engram",
      instructions: EngramTools.instructions,
      capabilities: .init(tools: .init(listChanged: false)))
    await server.withMethodHandler(ListTools.self) { _ in .init(tools: EngramTools.all) }
    await server.withMethodHandler(CallTool.self) { params in
      EngramTools.call(params.name, arguments: params.arguments, database: database)
    }
    try await server.start(transport: StdioTransport())
    await server.waitUntilCompleted()
  }
}
