import AppKit
import EngramKit
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var connection = ClaudeConnection.current()
  @State private var error: String?
  @State private var justChanged = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      claude
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
      ExportCard(database: model.database)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietCard()
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

/// "Export to Markdown…": every entry, project page and journal day as
/// plain files in a folder of your choice, ready to open in Obsidian.
private struct ExportCard: View {
  let database: AppDatabase?
  @State private var exported: URL?
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Export").font(.geist(15, .semibold)).foregroundStyle(Theme.text)
        Text(
          "Everything as Markdown: one file per entry, a page per project and one per journal "
            + "day. Open the folder in Obsidian or any editor."
        )
        .font(.geist(13))
        .foregroundStyle(Theme.textMuted)
        .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 10) {
        Button("Export to Markdown…", action: export)
          .buttonStyle(QuietButtonStyle(height: 30))
          .disabled(database == nil)
        if let exported {
          Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([exported])
          }
          .buttonStyle(.plain)
          .font(.geist(12.5))
          .foregroundStyle(Theme.accent)
        }
      }
      if let error {
        Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
      } else if let exported {
        Text("Saved to \(exported.path)")
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
          .lineLimit(2)
          .truncationMode(.middle)
      }
    }
  }

  private func export() {
    guard let database else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Export Here"
    panel.message = "Engram makes a new \"Engram Export\" folder inside the one you pick."
    guard panel.runModal() == .OK, let parent = panel.url else { return }
    do {
      exported = try database.exportMarkdown(into: parent)
      error = nil
    } catch {
      self.error = "Couldn't export: \(error.localizedDescription)"
      exported = nil
    }
  }
}
