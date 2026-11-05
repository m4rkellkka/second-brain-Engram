import EngramKit
import Foundation
import Observation

enum Section: String, CaseIterable, Identifiable {
  case inbox, projects, brain

  var id: String { rawValue }

  var title: String {
    switch self {
    case .inbox: "Inbox"
    case .projects: "Projects"
    case .brain: "Brain"
    }
  }

  var symbol: String {
    switch self {
    case .inbox: "tray"
    case .projects: "folder"
    case .brain: "point.3.connected.trianglepath.dotted"
    }
  }
}

/// App-wide state: the open database and what the window shows.
@Observable
final class AppModel {
  static let mainWindowID = "main"
  static let connectorFlag = "--mcp"

  let database: AppDatabase?
  let loadError: String?
  var section: Section = .inbox
  /// Bumped to move keyboard focus into the window's capture field.
  var captureFocusToken = 0
  /// Bumped when the connector wrote to the database from its own process.
  var externalChanges = 0
  var isSearching = false

  init(database: AppDatabase?, loadError: String? = nil) {
    self.database = database
    self.loadError = loadError
    NotificationCenter.default.addObserver(
      forName: ChangeSignal.notification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.externalChanges += 1 }
    }
  }

  /// The model for the running app, on the database file on disk.
  static func live() -> AppModel {
    do {
      return AppModel(database: try AppDatabase.open(at: databaseURL()))
    } catch {
      return AppModel(
        database: nil,
        loadError: "Couldn't open the Engram database: \(error.localizedDescription)")
    }
  }

  /// Debug builds accept `-EngramDatabasePath <file>` to keep test data
  /// away from the real database.
  static func databaseURL() throws -> URL {
    #if DEBUG
      if let path = UserDefaults.standard.string(forKey: "EngramDatabasePath") {
        return URL(filePath: path)
      }
    #endif
    return try AppDatabase.defaultURL()
  }

  func startNewThought() {
    section = .inbox
    captureFocusToken += 1
  }

  /// Saves a typed thought. Returns a message to show, or `nil` on success.
  func saveThought(_ text: String) -> String? {
    perform { try $0.saveTypedThought(text) }
  }

  /// Creates (or reuses) a project and files the entry into it.
  func fileEntry(_ entryID: String, intoNewProjectNamed name: String) -> String? {
    perform { db in
      let project = try db.createProject(named: name)
      try db.setProject(project.id, forEntry: entryID)
    }
  }

  func setProject(_ projectID: String?, forEntry entryID: String) -> String? {
    perform { try $0.setProject(projectID, forEntry: entryID) }
  }

  func setKind(_ kind: EntryKind, forEntry entryID: String) -> String? {
    perform { try $0.setKind(kind, forEntry: entryID) }
  }

  func confirm(_ entryID: String) -> String? {
    perform { try $0.confirmEntry(entryID) }
  }

  func createSuggestedProject(forEntry entryID: String) -> String? {
    perform { try $0.createSuggestedProject(forEntry: entryID) }
  }

  private func perform(_ work: (AppDatabase) throws -> Void) -> String? {
    guard let database else { return loadError }
    do {
      try work(database)
      return nil
    } catch let error as EngramError {
      return error.message
    } catch {
      return "Something went wrong: \(error.localizedDescription)"
    }
  }
}
