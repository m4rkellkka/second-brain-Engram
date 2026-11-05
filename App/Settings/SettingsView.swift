import SwiftUI

struct SettingsView: View {
  @State private var connection = ClaudeConnection.current()
  @State private var error: String?
  @State private var justChanged = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Claude Desktop").font(.geist(17, .semibold)).foregroundStyle(Theme.text)
        Text(
          "Connect Engram so Claude can save your conversations and look up your notes. "
            + "Then say \"save this to Engram\" at the end of a chat."
        )
        .font(.geist(13))
        .foregroundStyle(Theme.textMuted)
        .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 8) {
        Circle().fill(statusColor).frame(width: 8, height: 8)
        Text(statusText).font(.geist(13, .medium)).foregroundStyle(Theme.text)
      }

      if case .connectedElsewhere(let path) = connection {
        Text("Claude starts Engram from \(path). Connect again to use this copy.")
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 10) {
        switch connection {
        case .claudeMissing:
          Text("Install Claude Desktop first, then come back here.")
            .font(.geist(13))
            .foregroundStyle(Theme.textMuted)
        case .connected:
          Button("Disconnect") { run(ClaudeConnection.disconnect) }
        case .disconnected, .connectedElsewhere:
          Button("Connect to Claude Desktop") { run(ClaudeConnection.connect) }
            .keyboardShortcut(.defaultAction)
          if connection != .disconnected {
            Button("Disconnect") { run(ClaudeConnection.disconnect) }
          }
        }
      }

      if let error {
        Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
      } else if justChanged {
        Text("Done. Quit and reopen Claude Desktop so it picks up the change.")
          .font(.geist(12))
          .foregroundStyle(Theme.textMuted)
      }
    }
    .padding(24)
    .frame(width: 460, alignment: .leading)
    .background(Theme.background)
    .onAppear { connection = ClaudeConnection.current() }
  }

  private var statusText: String {
    switch connection {
    case .claudeMissing: "Claude Desktop isn't installed"
    case .disconnected: "Not connected"
    case .connected: "Connected"
    case .connectedElsewhere: "Connected to another copy of Engram"
    }
  }

  private var statusColor: Color {
    switch connection {
    case .connected: Theme.kindColor("note")
    case .connectedElsewhere: Theme.kindColor("task")
    default: Theme.textSubtle
    }
  }

  private func run(_ action: () -> String?) {
    error = action()
    justChanged = error == nil
    connection = ClaudeConnection.current()
  }
}
