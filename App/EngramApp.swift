import AppKit
import EngramKit
import SwiftUI

struct EngramApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var model: AppModel

  init() {
    Fonts.register()
    _model = State(initialValue: AppModel.live())
    ChangeSignal.startListening()
  }

  var body: some Scene {
    Window("Engram", id: AppModel.mainWindowID) {
      RootView()
        .environment(model)
        .frame(minWidth: 760, minHeight: 520)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
    .defaultSize(width: 1040, height: 720)
    // The top bar with the tabs takes the title bar's place.
    .windowStyle(.hiddenTitleBar)
    .commands { EngramCommands(model: model) }

    Settings {
      SettingsView()
        .environment(model)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    MenuBarExtra("Engram", systemImage: "point.3.connected.trianglepath.dotted") {
      MenuBarPanel()
        .environment(model)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
    .menuBarExtraStyle(.window)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.appearance = NSAppearance(named: .darkAqua)
  }

  /// Closing the window keeps Engram running in the menu bar.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}

struct EngramCommands: Commands {
  let model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Thought") {
        openWindow(id: AppModel.mainWindowID)
        model.startNewThought()
      }
      .keyboardShortcut("n")
    }
    CommandGroup(after: .newItem) {
      Button("Search…") {
        openWindow(id: AppModel.mainWindowID)
        model.isSearching = true
      }
      .keyboardShortcut("k")
    }
    // ⌘1… switch tabs, in the order they appear in the top bar.
    CommandGroup(before: .toolbar) {
      ForEach(Array(Section.allCases.enumerated()), id: \.element) { index, section in
        Button(section.title) {
          openWindow(id: AppModel.mainWindowID)
          model.section = section
          if section == .projects { model.openProjectID = nil }
        }
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
      }
      Divider()
    }
  }
}
