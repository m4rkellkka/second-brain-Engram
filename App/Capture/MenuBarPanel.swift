import AppKit
import SwiftUI

/// The popover behind the menu-bar icon: capture a thought from anywhere.
struct MenuBarPanel: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openWindow) private var openWindow
  @State private var waiting = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "point.3.connected.trianglepath.dotted")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Theme.accent)
        Text("New thought").font(.geist(13, .semibold)).foregroundStyle(Theme.text)
        Spacer()
        if waiting > 0 {
          Text("\(waiting) waiting in Inbox").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
        }
      }
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
    .task(id: model.externalChanges) {
      guard let database = model.database else { return }
      do {
        for try await value in database.waitingCountUpdates() { waiting = value }
      } catch {}
    }
  }
}

private struct PanelButton: View {
  let title: String
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
    }
    .buttonStyle(QuietButtonStyle(height: 28))
    .focusEffectDisabled()
  }
}

#Preview("Menu-bar panel") {
  MenuBarPanel()
    .environment(AppModel.preview(withSamples: false))
    .preferredColorScheme(.dark)
}
