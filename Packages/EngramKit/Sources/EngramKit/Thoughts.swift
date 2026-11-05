import CryptoKit
import Foundation
import GRDB

extension AppDatabase {
  public static let maxThoughtLength = 10_000

  /// Saves a thought typed in Engram: an `unsorted` capture with one `note`
  /// entry, in one transaction. Claude files it later on request.
  @discardableResult
  public func saveTypedThought(
    _ raw: String, timeZone: TimeZone = .current, now: Date = Date()
  ) throws -> Entry {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw EngramError.emptyThought }
    guard text.count <= Self.maxThoughtLength else {
      throw EngramError.thoughtTooLong(limit: Self.maxThoughtLength)
    }

    let capture = Capture(
      id: newID(), source: .typed, rawText: text, conversationRef: nil,
      contentHash: Self.contentHash(text), status: .unsorted,
      timeZone: timeZone.identifier, createdAt: now, sortedAt: nil)
    let entry = Entry(
      id: newID(), captureId: capture.id, projectId: nil, kind: .note, content: text,
      keywords: nil, url: nil, dueAt: nil, doneAt: nil, confidence: nil, needsReview: false,
      suggestedProject: nil, createdAt: now, updatedAt: now)

    try writer.write { db in
      try capture.insert(db)
      try entry.insert(db)
    }
    return entry
  }

  /// SHA-256 of the trimmed text, used to spot a summary saved twice.
  static func contentHash(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
