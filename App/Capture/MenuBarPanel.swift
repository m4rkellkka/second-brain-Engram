import AppKit
import SwiftUI

/// The popover behind the menu-bar icon: capture a thought from anywhere.
struct MenuBarPanel: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("New thought")
        .font(.geist(12, .medium))
        .foregroundStyle(Theme.textMuted)
      CaptureBox(editorHeight: 96, focusWhenWindowActivates: true)
      HStack {
        PanelButton(title: "Open Engram", symbol: "macwindow") {
          openWindow(id: AppModel.mainWindowID)
          NSApp.activate()
        }
        Spacer()
        PanelButton(title: "Quit", symbol: "power") { NSApp.terminate(nil) }
      }
    }
    .padding(14)
    .frame(width: 380)
    .background(Theme.background)
  }
}

private struct PanelButton: View {
  let title: String
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.geist(12.5))
        .foregroundStyle(Theme.textMuted)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
