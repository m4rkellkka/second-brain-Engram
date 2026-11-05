import Foundation

/// Reads and edits Claude Desktop's `claude_desktop_config.json`, touching
/// only `mcpServers.engram` and keeping every other setting as it was.
public enum ClaudeDesktopConfig {
  public static let serverKey = "engram"

  public struct Server: Equatable, Sendable {
    public var command: String
    public var args: [String]

    public init(command: String, args: [String]) {
      self.command = command
      self.args = args
    }
  }

  public enum ConfigError: Error, Equatable {
    case notAnObject
  }

  /// `~/Library/Application Support/Claude/claude_desktop_config.json`.
  public static func defaultURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/Claude/claude_desktop_config.json")
  }

  /// The Engram entry in a config file's contents, if there is one.
  public static func server(in data: Data?) -> Server? {
    guard let data, !data.isEmpty,
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let servers = root["mcpServers"] as? [String: Any],
      let entry = servers[serverKey] as? [String: Any],
      let command = entry["command"] as? String
    else { return nil }
    return Server(command: command, args: entry["args"] as? [String] ?? [])
  }

  /// The config with Engram added (or updated). Missing or empty files start fresh.
  public static func connecting(_ server: Server, to data: Data?) throws -> Data {
    var root = try object(from: data)
    var servers = root["mcpServers"] as? [String: Any] ?? [:]
    servers[serverKey] = ["command": server.command, "args": server.args]
    root["mcpServers"] = servers
    return try serialize(root)
  }

  /// The config without Engram.
  public static func disconnecting(_ data: Data?) throws -> Data {
    var root = try object(from: data)
    if var servers = root["mcpServers"] as? [String: Any] {
      servers[serverKey] = nil
      root["mcpServers"] = servers
    }
    return try serialize(root)
  }

  /// Writes the new contents, keeping the previous file as
  /// `claude_desktop_config.json.engram-backup`.
  public static func write(_ data: Data, to url: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if fileManager.fileExists(atPath: url.path) {
      let backup = url.appendingPathExtension("engram-backup")
      try? fileManager.removeItem(at: backup)
      try fileManager.copyItem(at: url, to: backup)
    }
    try data.write(to: url, options: .atomic)
  }

  private static func object(from data: Data?) throws -> [String: Any] {
    guard let data, !data.isEmpty else { return [:] }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ConfigError.notAnObject
    }
    return root
  }

  private static func serialize(_ root: [String: Any]) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }
}
