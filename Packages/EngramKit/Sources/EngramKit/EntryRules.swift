import Foundation

/// Turns what Claude sent into entries Engram can store, or explains what is wrong.
enum EntryRules {
  static let maxEntries = 30
  static let maxContentLength = 2_000
  static let maxSummaryLength = 20_000
  static let maxKeywords = 8
  /// Below this confidence an entry shows the "not sure" card.
  static let reviewThreshold = 0.7

  struct Prepared {
    var kind: EntryKind
    var content: String
    var projectID: String?
    var suggestedProject: String?
    var dueAt: Date?
    var url: String?
    var confidence: Double?
    var keywords: [String]
    var needsReview: Bool
  }

  static func prepare(
    _ inputs: [EntryInput], projects: [Project], timeZone: TimeZone
  ) throws(InputError) -> [Prepared] {
    guard !inputs.isEmpty else { throw InputError("entries: send at least one entry.") }
    guard inputs.count <= maxEntries else {
      throw InputError("entries: at most \(maxEntries) entries per call.")
    }
    var problems: [String] = []
    var prepared: [Prepared] = []
    for (index, input) in inputs.enumerated() {
      do throws(InputError) {
        prepared.append(try prepare(input, projects: projects, timeZone: timeZone))
      } catch {
        problems += error.problems.map { "entries[\(index)].\($0)" }
      }
    }
    guard problems.isEmpty else { throw InputError(problems) }
    return prepared
  }

  static func prepare(
    _ input: EntryInput, projects: [Project], timeZone: TimeZone
  ) throws(InputError) -> Prepared {
    var problems: [String] = []

    let kind = EntryKind(rawValue: input.kind.lowercased())
    if kind == nil { problems.append("kind: use idea, task, note or link.") }

    let content = input.content.trimmingCharacters(in: .whitespacesAndNewlines)
    if content.isEmpty { problems.append("content: must not be empty.") }
    if content.count > maxContentLength {
      problems.append("content: keep it under \(maxContentLength) characters.")
    }

    var dueAt: Date?
    if let raw = input.dueAt?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
      dueAt = parseDate(raw, timeZone: timeZone)
      if dueAt == nil {
        problems.append("dueAt: use ISO 8601, e.g. 2026-11-07 or 2026-11-07T18:00:00+03:00.")
      }
    }

    var url: String?
    if let raw = input.url?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
      if let parsed = URL(string: raw), ["http", "https"].contains(parsed.scheme?.lowercased()) {
        url = raw
      } else {
        problems.append("url: must be an http or https link.")
      }
    }
    if kind == .link && url == nil && problems.allSatisfy({ !$0.hasPrefix("url") }) {
      problems.append("url: a link entry needs its url.")
    }

    var confidence = input.confidence
    if let value = confidence, !(0...1).contains(value) {
      problems.append("confidence: use a number from 0 to 1.")
      confidence = nil
    }

    guard problems.isEmpty, let kind else { throw InputError(problems) }

    let project = match(input.projectSlug, in: projects)
    let suggestion =
      clean(input.suggestedProject) ?? (project == nil ? clean(input.projectSlug) : nil)
    let needsReview = project == nil || (confidence ?? 1) < reviewThreshold

    return Prepared(
      kind: kind, content: content, projectID: project?.id,
      suggestedProject: project == nil ? suggestion : nil,
      dueAt: dueAt, url: url, confidence: confidence,
      keywords: normalizeKeywords(input.keywords ?? []), needsReview: needsReview)
  }

  /// An active project by slug, or by name when Claude sent the name instead.
  static func match(_ raw: String?, in projects: [Project]) -> Project? {
    guard let key = clean(raw)?.lowercased() else { return nil }
    return projects.first { $0.slug == key }
      ?? projects.first { $0.name.lowercased() == key }
      ?? projects.first { $0.slug == ProjectNaming.slugify(key) }
  }

  /// Lowercased single words, deduplicated, at most `maxKeywords`.
  static func normalizeKeywords(_ raw: [String]) -> [String] {
    var seen = Set<String>()
    var words: [String] = []
    for phrase in raw {
      for word in phrase.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
        let word = String(word.prefix(40))
        if seen.insert(word).inserted { words.append(word) }
      }
    }
    return Array(words.prefix(maxKeywords))
  }

  /// `2026-11-07` (start of that day in the user's zone), a full ISO 8601
  /// date-time with offset, or one without offset read in the user's zone.
  static func parseDate(_ raw: String, timeZone: TimeZone) -> Date? {
    let withOffset = ISO8601DateFormatter()
    withOffset.formatOptions = [.withInternetDateTime]
    if let date = withOffset.date(from: raw) { return date }
    withOffset.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withOffset.date(from: raw) { return date }

    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.timeZone = timeZone
    for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
      local.dateFormat = format
      if let date = local.date(from: raw) { return date }
    }
    return nil
  }

  private static func clean(_ raw: String?) -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return String(value.prefix(ProjectNaming.maxNameLength))
  }
}
