import Foundation
import Testing

@testable import EngramKit

@Suite struct ClaudeDesktopConfigTests {
  let server = ClaudeDesktopConfig.Server(
    command: "/Applications/Engram.app/Contents/MacOS/Engram", args: ["--mcp"])

  func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func connectKeepsEverythingElse() throws {
    let existing = Data(
      """
      {"preferences": {"menuBarEnabled": false},
       "mcpServers": {"other": {"command": "/bin/other"}}}
      """.utf8)
    let updated = try ClaudeDesktopConfig.connecting(server, to: existing)
    let root = try object(updated)
    #expect((root["preferences"] as? [String: Any])?["menuBarEnabled"] as? Bool == false)
    let servers = try #require(root["mcpServers"] as? [String: Any])
    #expect(servers["other"] != nil)
    #expect(ClaudeDesktopConfig.server(in: updated) == server)
  }

  @Test func connectStartsAMissingFile() throws {
    let created = try ClaudeDesktopConfig.connecting(server, to: nil)
    #expect(ClaudeDesktopConfig.server(in: created) == server)
  }

  @Test func disconnectRemovesOnlyEngram() throws {
    let connected = try ClaudeDesktopConfig.connecting(
      server, to: Data(#"{"mcpServers": {"other": {"command": "x"}}}"#.utf8))
    let removed = try ClaudeDesktopConfig.disconnecting(connected)
    #expect(ClaudeDesktopConfig.server(in: removed) == nil)
    let servers = try #require(try object(removed)["mcpServers"] as? [String: Any])
    #expect(servers["other"] != nil)
  }

  @Test func refusesToRewriteSomethingThatIsNotAnObject() {
    #expect(throws: ClaudeDesktopConfig.ConfigError.notAnObject) {
      try ClaudeDesktopConfig.connecting(server, to: Data("[1, 2]".utf8))
    }
  }

  @Test func writeKeepsABackup() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "claude_desktop_config.json")
    try ClaudeDesktopConfig.write(Data("{}".utf8), to: url)
    try ClaudeDesktopConfig.write(Data(#"{"a": 1}"#.utf8), to: url)
    let backup = try String(
      contentsOf: url.appendingPathExtension("engram-backup"), encoding: .utf8)
    #expect(backup == "{}")
  }
}
