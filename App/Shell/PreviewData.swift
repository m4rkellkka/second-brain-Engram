import EngramKit
import Foundation

extension AppModel {
  /// A model on a fresh in-memory database, for Xcode previews.
  /// Previews never touch the real database file.
  static func preview(withSamples: Bool = true) -> AppModel {
    Fonts.register()
    do {
      let database = try AppDatabase.inMemory()
      if withSamples { try addSamples(to: database) }
      return AppModel(database: database)
    } catch {
      return AppModel(database: nil, loadError: "Preview database failed: \(error)")
    }
  }

  private static func addSamples(to database: AppDatabase) throws {
    let now = Date()
    let engram = try database.createProject(named: "Engram")
    try database.createProject(named: "Учёба")
    let decision = try database.saveTypedThought(
      "Решил строить Engram как нативное приложение на Swift, без Docker и логина.",
      now: now.addingTimeInterval(-3 * 3600))
    try database.setProject(engram.id, forEntry: decision.id)
    try database.saveTypedThought(
      "Купить новую клавиатуру\nи подставку для ноутбука", now: now.addingTimeInterval(-20 * 60))
    try database.saveTypedThought(
      "Read the GRDB docs on ValueObservation", now: now.addingTimeInterval(-26 * 3600))
  }
}
