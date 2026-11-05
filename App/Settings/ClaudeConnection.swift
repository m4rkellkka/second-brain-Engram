import AppKit
import EngramKit
import Foundation

/// Whether Claude Desktop knows how to start Engram's connector.
enum ClaudeConnection: Equatable {
  case claudeMissing
  case disconnected
  case connected
  /// Connected, but to an Engram.app at another path (moved or a dev build).
  case connectedElsewhere(String)

  static let claudeBundleID = "com.anthropic.claudefordesktop"

  /// How Claude Desktop should start this copy of Engram.
  static func currentServer() -> ClaudeDesktopConfig.Server? {
    guard let executable = Bundle.main.executablePath else { return nil }
    var args = [AppModel.connectorFlag]
    #if DEBUG
      if let path = UserDefaults.standard.string(forKey: "EngramDatabasePath") {
        args += ["-EngramDatabasePath", path]
      }
    #endif
    return .init(command: executable, args: args)
  }

  static func current() -> ClaudeConnection {
    let url = ClaudeDesktopConfig.defaultURL()
    let hasClaude =
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleID) != nil
      || FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path)
    guard hasClaude else { return .claudeMissing }
    guard let configured = ClaudeDesktopConfig.server(in: try? Data(contentsOf: url)) else {
      return .disconnected
    }
    return configured == currentServer() ? .connected : .connectedElsewhere(configured.command)
  }

  /// Returns an error message, or `nil` on success.
  static func connect() -> String? {
    guard let server = currentServer() else { return "Can't find Engram's own executable." }
    return update { try ClaudeDesktopConfig.connecting(server, to: $0) }
  }

  static func disconnect() -> String? {
    update { try ClaudeDesktopConfig.disconnecting($0) }
  }

  private static func update(_ change: (Data?) throws -> Data) -> String? {
    let url = ClaudeDesktopConfig.defaultURL()
    do {
      let existing =
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
      try ClaudeDesktopConfig.write(try change(existing), to: url)
      return nil
    } catch ClaudeDesktopConfig.ConfigError.notAnObject {
      return "Claude Desktop's config file isn't a JSON object, so Engram left it alone."
    } catch {
      return "Couldn't update Claude Desktop's config: \(error.localizedDescription)"
    }
  }
}
