import Foundation
import GRDB

public enum EntryKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
  case idea, task, note, link
}

public enum CaptureSource: String, Codable, Sendable, DatabaseValueConvertible {
  case typed, claude
}

public enum CaptureStatus: String, Codable, Sendable, DatabaseValueConvertible {
  case unsorted, sorted
}

/// Who wrote a piece of project context. Anything the user wrote wins.
public enum ContextSource: String, Codable, Sendable, DatabaseValueConvertible {
  case ai, user
}

public enum ContextSection: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
  case stack, decision, idea

  public var title: String {
    switch self {
    case .stack: "Stack"
    case .decision: "Decisions"
    case .idea: "Open ideas"
    }
  }
}

/// Columns are snake_case in SQLite and camelCase in Swift.
public protocol EngramRecord: Codable, FetchableRecord, PersistableRecord {}

extension EngramRecord {
  public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
    .convertFromSnakeCase
  }
  public static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
    .convertToSnakeCase
  }
}

public struct Project: EngramRecord, Identifiable, Hashable, Sendable {
  public static let databaseTableName = "projects"

  public var id: String
  public var name: String
  public var slug: String
  public var color: String
  public var status: String?
  public var summary: String?
  public var summarySource: ContextSource
  public var statusSource: ContextSource
  public var contextUpdatedAt: Date?
  public var archivedAt: Date?
  public var createdAt: Date
}

public struct Capture: EngramRecord, Identifiable, Hashable, Sendable {
  public static let databaseTableName = "captures"

  public var id: String
  public var source: CaptureSource
  public var rawText: String
  public var conversationRef: String?
  public var contentHash: String
  public var status: CaptureStatus
  public var timeZone: String
  public var createdAt: Date
  public var sortedAt: Date?
}

public struct Entry: EngramRecord, Identifiable, Hashable, Sendable {
  public static let databaseTableName = "entries"
  static let project = belongsTo(Project.self)
  static let capture = belongsTo(Capture.self)

  public var id: String
  public var captureId: String?
  public var projectId: String?
  public var kind: EntryKind
  public var content: String
  public var keywords: String?
  public var url: String?
  public var dueAt: Date?
  public var doneAt: Date?
  public var confidence: Double?
  public var needsReview: Bool
  public var suggestedProject: String?
  public var createdAt: Date
  public var updatedAt: Date
}

/// A line in a project's live context: stack, a decision or an open idea.
public struct ContextItem: EngramRecord, Identifiable, Hashable, Sendable {
  public static let databaseTableName = "project_context_items"

  public var id: String
  public var projectId: String
  public var section: ContextSection
  public var text: String
  public var source: ContextSource
  /// JSON array of the entries this item came from.
  public var entryIds: String
  public var createdAt: Date
  public var dismissedAt: Date?

  public var entryIDList: [String] {
    (try? JSONDecoder().decode([String].self, from: Data(entryIds.utf8))) ?? []
  }
}

/// One Inbox row: an entry, the project it is filed in and where it came from.
public struct InboxItem: Decodable, FetchableRecord, Identifiable, Hashable, Sendable {
  public var entry: Entry
  public var project: Project?
  public var capture: Capture?
  public var id: String { entry.id }
}

func newID() -> String {
  UUID().uuidString.lowercased()
}
