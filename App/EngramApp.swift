import EngramKit
import SwiftUI

@main
struct EngramApp: App {
  var body: some Scene {
    Window("Engram", id: "main") {
      Text("Engram \(EngramKit.schemaVersion)")
    }
  }
}
