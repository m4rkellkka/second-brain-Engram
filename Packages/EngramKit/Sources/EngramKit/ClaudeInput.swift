import Foundation

/// One entry as Claude sends it through the connector.
public struct EntryInput: Codable, Sendable, Equatable {
  public var kind: String
  public var content: String
  public var projectSlug: String?
  public var suggestedProject: String?
  public var dueAt: String?
  public var url: String?
  public var confidence: Double?
  public var keywords: [String]?

  public init(
    kind: String, content: String, projectSlug: String? = nil, suggestedProject: String? = nil,
    dueAt: String? = nil, url: String? = nil, confidence: Double? = nil, keywords: [String]? = nil
  ) {
    self.kind = kind
    self.content = content
    self.projectSlug = projectSlug
    self.suggestedProject = suggestedProject
    self.dueAt = dueAt
    self.url = url
    self.confidence = confidence
    self.keywords = keywords
  }
}

/// `save_to_engram`: a conversation summary, already split into entries.
public struct SaveRequest: Codable, Sendable, Equatable {
  public var summary: String
  public var entries: [EntryInput]
  public var conversationRef: String?
  public var timeZone: String?
  public var contextUpdates: [ContextUpdateInput]?

  public init(
    summary: String, entries: [EntryInput], conversationRef: String? = nil,
    timeZone: String? = nil, contextUpdates: [ContextUpdateInput]? = nil
  ) {
    self.summary = summary
    self.entries = entries
    self.conversationRef = conversationRef
    self.timeZone = timeZone
    self.contextUpdates = contextUpdates
  }
}

/// What a save returns to Claude, so it can tell the user where things went.
public struct SaveResult: Codable, Sendable, Equatable {
  public struct Saved: Codable, Sendable, Equatable {
    public var id: String
    public var kind: String
    public var content: String
    public var project: String?
    public var needsReview: Bool
    public var dueAt: String?
  }

  public var captureId: String
  public var duplicate: Bool
  public var entries: [Saved]
  public var context: [ContextOutcome]?
}

/// Input problems reported back to Claude so it can fix the call.
public struct InputError: Error, Equatable, Sendable, CustomStringConvertible {
  public var problems: [String]
  public var description: String { problems.joined(separator: "\n") }

  init(_ problems: [String]) { self.problems = problems }
  init(_ problem: String) { self.problems = [problem] }
}
