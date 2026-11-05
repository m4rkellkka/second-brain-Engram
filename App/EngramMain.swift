import EngramKit
import EngramMCP
import Foundation

/// One executable, two modes. Claude Desktop starts `Engram --mcp` and talks
/// to it over stdin/stdout; any other launch opens the app.
@main
enum EngramMain {
  static func main() {
    if CommandLine.arguments.contains(AppModel.connectorFlag) {
      runConnector()
    } else {
      EngramApp.main()
    }
  }

  /// Serves MCP until Claude closes the pipe. Nothing but protocol messages
  /// may go to stdout, so problems are written to stderr.
  private static func runConnector() {
    let database: AppDatabase
    do {
      database = try AppDatabase.open(at: AppModel.databaseURL())
    } catch {
      FileHandle.standardError.write(Data("Engram: can't open the database: \(error)\n".utf8))
      exit(1)
    }
    Task {
      do {
        try await EngramServer.run(database: database, version: Bundle.main.appVersion)
        exit(0)
      } catch {
        FileHandle.standardError.write(Data("Engram connector stopped: \(error)\n".utf8))
        exit(1)
      }
    }
    dispatchMain()
  }
}
