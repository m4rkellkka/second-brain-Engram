import SwiftUI

struct SettingsView: View {
  @State private var connection = ClaudeConnection.current()
  @State private var error: String?
  @State private var justChanged = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      claude
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
      about
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietCard()
    }
    .padding(24)
    .frame(width: 560, alignment: .leading)
    .background(Theme.background)
    .onAppear { connection = ClaudeConnection.current() }
  }

  private var about: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("About").font(.geist(15, .semibold)).foregroundStyle(Theme.text)
        Text("Engram \(Bundle.main.appVersion) · open source, MIT")
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
      }
      Spacer()
      if let url = URL(string: "https://github.com/m4rkellkka/second-brain-Engram") {
        Link("GitHub →", destination: url)
          .font(.geist(12.5))
          .foregroundStyle(Theme.accent)
      }
    }
  }

  private var claude: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Claude Desktop").font(.geist(15, .semibold)).foregroundStyle(Theme.text)
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
            .buttonStyle(QuietButtonStyle(height: 30))
        case .disconnected, .connectedElsewhere:
          Button("Connect to Claude Desktop") { run(ClaudeConnection.connect) }
            .buttonStyle(AccentButtonStyle(height: 30))
            .keyboardShortcut(.defaultAction)
          if connection != .disconnected {
            Button("Disconnect") { run(ClaudeConnection.disconnect) }
              .buttonStyle(QuietButtonStyle(height: 30))
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
