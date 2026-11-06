import EngramKit
import Foundation
import GRDB
import Observation

/// The window's tabs, in the order they appear (and their ⌘1… shortcuts).
enum Section: String, CaseIterable, Identifiable {
  case today, inbox, projects, brain

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today: "Today"
    case .inbox: "Inbox"
    case .projects: "Projects"
    case .brain: "Brain"
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
  /// The open tab; remembered so Engram reopens where you left it.
  var section: Section = AppModel.savedSection() {
    didSet { UserDefaults.standard.set(section.rawValue, forKey: Self.sectionKey) }
  }
  /// Bumped to move keyboard focus into the window's capture field.
  var captureFocusToken = 0
  /// Bumped when the connector wrote to the database from its own process.
  var externalChanges = 0
  var isSearching = false
  /// The project page open in the Projects section, if any.
  var openProjectID: String?

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
      let model = AppModel(database: try AppDatabase.open(at: databaseURL()))
      #if DEBUG
        model.applyDebugLaunchArguments()
      #endif
      return model
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

  func openProject(_ projectID: String) {
    openProjectID = projectID
    section = .projects
  }

  /// ⌘N: focus a capture field, staying on the Inbox if it is open.
  /// A project the Brain should fly to the next time it shows.
  var brainFocusRequest: String?

  /// "Show in Brain" on a project page.
  func showInBrain(_ projectID: String) {
    brainFocusRequest = projectID
    section = .brain
  }

  func startNewThought() {
    if section != .inbox { section = .today }
    captureFocusToken += 1
  }

  private static let sectionKey = "lastSection"

  /// The tab open when Engram last quit; Today the first time.
  private static func savedSection() -> Section {
    UserDefaults.standard.string(forKey: sectionKey).flatMap(Section.init(rawValue:)) ?? .today
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

  func setDone(_ done: Bool, entryID: String) -> String? {
    perform { try $0.setDone(done, entryID: entryID) }
  }

  func createProject(named name: String) -> String? {
    perform { try $0.createProject(named: name) }
  }

  /// Runs any database change and returns a message to show on failure.
  func change(_ work: (AppDatabase) throws -> Void) -> String? {
    perform(work)
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

  #if DEBUG
    /// `-EngramSection projects` and `-EngramOpenProject <slug>` open a
    /// screen at launch, for screenshots and manual checks.
    private func applyDebugLaunchArguments() {
      let defaults = UserDefaults.standard
      if let raw = defaults.string(forKey: "EngramSection"), let value = Section(rawValue: raw) {
        section = value
      }
      if let slug = defaults.string(forKey: "EngramOpenProject"),
        let id = try? database?.writer.read({ db in
          try String.fetchOne(db, sql: "select id from projects where slug = ?", arguments: [slug])
        })
      {
        openProject(id)
      }
    }
  #endif
}
