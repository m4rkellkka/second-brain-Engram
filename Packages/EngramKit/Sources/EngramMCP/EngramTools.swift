import EngramKit
import Foundation
import GRDB
import MCP

/// The tools Claude sees, and what each one does.
public enum EngramTools {
  public static let instructions = """
    Engram is the user's local second brain: notes, ideas, tasks and decisions filed into \
    projects. Before answering questions about the user's projects, plans, decisions or tasks, \
    look them up with search_entries, get_project_context or list_tasks. Save only when the user \
    asks you to save, remember or file something. Keep project pages current with \
    update_project (description, status, stack, decisions, ideas) and tick finished tasks with \
    complete_task. The user also keeps a journal, one page per day: write_journal adds to it \
    only when the user explicitly asks for their journal or diary ("запиши в дневник"); \
    "save this to Engram" means save_to_engram alone, never the journal. get_journal reads the \
    journal when they ask how they felt or what happened on some days. Reply to the user in \
    their language.
    """

  static let entryRules = """
    Split the content into small entries, one task, idea, decision, fact or link each:
    - kind: "task" = something the user should do (put any deadline in dueAt); "idea" = a \
    possibility not decided yet; "note" = a fact or a decision; "link" = a URL worth keeping \
    (url required).
    - content: one or two self-contained sentences in the user's language, understandable \
    without the conversation.
    - projectSlug: the slug of the matching project from list_projects, or null if none fits. \
    Never invent a slug. If a new project is clearly implied, put its short name in \
    suggestedProject.
    - confidence: 0 to 1, how sure you are about kind and project. Below 0.7 the user checks it.
    - keywords: 3 to 6 words in base form (nominative singular, infinitive) in the user's \
    language, plus English equivalents for key terms. They power search and graph links.
    - dueAt: ISO 8601. Resolve relative dates ("Friday", "завтра") against the local time and \
    time zone that list_projects returns.
    """

  static let contextRules = """
    contextUpdates (optional): keep the project pages current. For each project the \
    conversation changed, send its projectSlug and only what is new:
    - add: new items, each with section "stack" (tools, tech, materials the project uses), \
    "decision" (something settled) or "idea" (an open possibility), a short text and \
    fromEntries, the indexes of this call's entries it comes from. Items are only added, never \
    replaced; repeats are skipped. Check get_project_context first to avoid restating items.
    - summary: a new 1 to 3 sentence description, only if the project itself changed. \
    - status: a few words like "MVP in progress" or "paused", only if it changed.
    If the user wrote the summary or status, Engram keeps theirs and says so in the result. \
    You cannot override it; tell the user they can press "Let Claude update" on the project \
    page in Engram if they want your text instead.
    """

  static let contextSchema: Value = [
    "type": "array",
    "items": [
      "type": "object",
      "properties": [
        "projectSlug": ["type": "string"],
        "summary": ["type": "string"],
        "status": ["type": "string"],
        "add": [
          "type": "array",
          "items": [
            "type": "object",
            "properties": [
              "section": ["type": "string", "enum": ["stack", "decision", "idea"]],
              "text": ["type": "string"],
              "fromEntries": ["type": "array", "items": ["type": "integer", "minimum": 0]],
            ],
            "required": ["section", "text"],
          ],
        ],
      ],
      "required": ["projectSlug"],
    ],
  ]

  static let entrySchema: Value = [
    "type": "object",
    "properties": [
      "kind": ["type": "string", "enum": ["task", "idea", "note", "link"]],
      "content": ["type": "string"],
      "projectSlug": ["type": ["string", "null"]],
      "suggestedProject": ["type": ["string", "null"]],
      "confidence": ["type": "number", "minimum": 0, "maximum": 1],
      "keywords": ["type": "array", "items": ["type": "string"]],
      "dueAt": ["type": ["string", "null"], "description": "ISO 8601 date or date-time"],
      "url": ["type": ["string", "null"]],
    ],
    "required": ["kind", "content", "confidence", "keywords"],
  ]

  public static let all: [Tool] = [
    Tool(
      name: "save_to_engram",
      title: "Save to Engram",
      description: """
        Save the gist of this conversation to the user's Engram. Use it when the user says \
        "save this to Engram", "сохрани в Engram", "запомни" or similar. Call list_projects \
        first so entries land in the right project.
        summary: 2 to 6 sentences on what was discussed and decided, in the user's language.
        \(entryRules)
        \(contextRules)
        To change a project page without new entries, call update_project instead.
        conversationRef: a short title of the conversation. Engram skips a summary it already \
        saved. Afterwards tell the user briefly where each entry went; entries with needsReview \
        wait for the user's check in the Engram Inbox.
        """,
      inputSchema: [
        "type": "object",
        "properties": [
          "summary": ["type": "string"],
          "entries": ["type": "array", "items": entrySchema, "minItems": 1],
          "conversationRef": ["type": "string"],
          "timeZone": ["type": "string", "description": "IANA time zone, if known"],
          "contextUpdates": contextSchema,
        ],
        "required": ["summary", "entries"],
      ],
      annotations: .init(
        title: "Save to Engram", readOnlyHint: false, destructiveHint: false,
        idempotentHint: true, openWorldHint: false)),
    Tool(
      name: "list_projects",
      title: "List Engram projects",
      description: """
        The user's active projects (slug, name, status, summary, number of entries), plus the \
        current local time and time zone. Call it before saving or sorting.
        """,
      inputSchema: ["type": "object", "properties": [:]],
      annotations: .init(title: "List projects", readOnlyHint: true, openWorldHint: false)),
    Tool(
      name: "get_project_context",
      title: "Get a project's context",
      description: """
        One project's live context: summary and status (and whether the user or Claude wrote \
        them), stack, decisions, open ideas, open tasks and recent entries. Use it when the user \
        asks about a project, wants to continue working on it, or before sending contextUpdates.
        """,
      inputSchema: [
        "type": "object",
        "properties": ["slug": ["type": "string"]],
        "required": ["slug"],
      ],
      annotations: .init(title: "Project context", readOnlyHint: true, openWorldHint: false)),
    Tool(
      name: "search_entries",
      title: "Search Engram",
      description: """
        Full-text search over the user's entries, best match first. Every word must match the \
        start of a word, so use a few base-form words, not a sentence; try Russian and English \
        words separately if the first search finds nothing.
        """,
      inputSchema: [
        "type": "object",
        "properties": [
          "query": ["type": "string"],
          "projectSlug": ["type": "string"],
          "kind": ["type": "string", "enum": ["task", "idea", "note", "link"]],
          "limit": ["type": "integer", "minimum": 1, "maximum": 50],
        ],
        "required": ["query"],
      ],
      annotations: .init(title: "Search", readOnlyHint: true, openWorldHint: false)),
    Tool(
      name: "list_tasks",
      title: "List open tasks",
      description:
        "Open tasks, soonest due first, optionally for one project or due before a date.",
      inputSchema: [
        "type": "object",
        "properties": [
          "projectSlug": ["type": "string"],
          "dueBefore": ["type": "string", "description": "ISO 8601 date or date-time"],
        ],
      ],
      annotations: .init(title: "Open tasks", readOnlyHint: true, openWorldHint: false)),
    Tool(
      name: "update_project",
      title: "Update a project page",
      description: """
        Update one project's page in Engram: its description (summary), status, and new stack, \
        decision or idea items. Use it whenever the user asks to update a project, or when a \
        conversation changed what a project is, where it stands or what was decided, even if \
        nothing new needs saving as entries. Call get_project_context first and send only what \
        is new. Items are only added, never replaced; repeats are skipped; entryIds (from \
        get_project_context, search_entries or list_tasks) link an item to the notes behind it.
        summary: 1 to 3 sentences on what the project is. status: a few words like \
        "prototype test" or "paused". If the user wrote the summary or status, Engram keeps \
        theirs and says so; you cannot override it, but the user can press "Let Claude update" \
        on the project page.
        """,
      inputSchema: [
        "type": "object",
        "properties": [
          "projectSlug": ["type": "string"],
          "summary": ["type": "string"],
          "status": ["type": "string"],
          "add": [
            "type": "array",
            "items": [
              "type": "object",
              "properties": [
                "section": ["type": "string", "enum": ["stack", "decision", "idea"]],
                "text": ["type": "string"],
                "entryIds": ["type": "array", "items": ["type": "string"]],
              ],
              "required": ["section", "text"],
            ],
          ],
        ],
        "required": ["projectSlug"],
      ],
      annotations: .init(
        title: "Update project", readOnlyHint: false, destructiveHint: false,
        idempotentHint: true, openWorldHint: false)),
    Tool(
      name: "complete_task",
      title: "Complete a task",
      description: """
        Mark a task as done in Engram (or open it again with done: false). Use it when the user \
        says a task is finished, or when the conversation shows it was done. Find the task's id \
        with list_tasks or get_project_context.
        """,
      inputSchema: [
        "type": "object",
        "properties": [
          "entryId": ["type": "string"],
          "done": ["type": "boolean"],
        ],
        "required": ["entryId"],
      ],
      annotations: .init(
        title: "Complete task", readOnlyHint: false, destructiveHint: false,
        idempotentHint: true, openWorldHint: false)),
    Tool(
      name: "list_unsorted",
      title: "List unsorted thoughts",
      description: """
        Thoughts the user typed into Engram that are not sorted yet. Use it when the user asks \
        to sort or clean up the Engram inbox ("разбери инбокс"), then call sort_capture for each.
        """,
      inputSchema: ["type": "object", "properties": [:]],
      annotations: .init(title: "Unsorted thoughts", readOnlyHint: true, openWorldHint: false)),
    Tool(
      name: "write_journal",
      title: "Write to the journal",
      description: """
        Add a paragraph to the user's journal (diary) in Engram. Use it only when the user \
        explicitly asks for the journal or diary ("запиши в дневник", "write to my journal"). \
        Don't use it for "save this to Engram" or "запомни"; those go to save_to_engram only, \
        even when the user talks about their day. Write in the first person, as the user, in \
        their language: what happened and how they felt, 2 to 8 sentences, keeping their own \
        words where you can. Don't invent anything they didn't say.
        date: the local day (YYYY-MM-DD) it is about; leave it out for today. Use it when the \
        user talks about an earlier day ("запиши за вчера"); resolve it against the local time \
        from list_projects. Future days are rejected.
        The paragraph is added to the day; Engram never changes what is already there, \
        including what the user wrote. Afterwards tell the user it is in the Journal tab.
        """,
      inputSchema: [
        "type": "object",
        "properties": [
          "text": ["type": "string"],
          "date": ["type": "string", "description": "YYYY-MM-DD, local day; omit for today"],
        ],
        "required": ["text"],
      ],
      annotations: .init(
        title: "Write journal", readOnlyHint: false, destructiveHint: false,
        idempotentHint: true, openWorldHint: false)),
    Tool(
      name: "get_journal",
      title: "Read the journal",
      description: """
        The user's journal days in a date range (inclusive, local days, YYYY-MM-DD), oldest \
        first: each day's paragraphs with who wrote them. Defaults to the last 7 days; at most \
        62 days at once. Use it when the user asks how they felt, how a week went, or what they \
        wrote about a day ("как я себя чувствовал на прошлой неделе?"). Answer from what is \
        written; say so if a day has nothing.
        """,
      inputSchema: [
        "type": "object",
        "properties": [
          "from": ["type": "string", "description": "YYYY-MM-DD"],
          "to": ["type": "string", "description": "YYYY-MM-DD"],
        ],
      ],
      annotations: .init(title: "Read journal", readOnlyHint: true, openWorldHint: false)),
    Tool(
      name: "sort_capture",
      title: "Sort a typed thought",
      description: """
        File one thought from list_unsorted into entries. Resolve relative dates against the \
        thought's createdAt and timeZone, not today.
        \(entryRules)
        \(contextRules)
        """,
      inputSchema: [
        "type": "object",
        "properties": [
          "captureId": ["type": "string"],
          "entries": ["type": "array", "items": entrySchema, "minItems": 1],
          "contextUpdates": contextSchema,
        ],
        "required": ["captureId", "entries"],
      ],
      annotations: .init(
        title: "Sort thought", readOnlyHint: false, destructiveHint: false,
        idempotentHint: false, openWorldHint: false)),
  ]

  /// Runs one tool call. Failures come back as `isError` results, so Claude
  /// can read what to fix and try again.
  public static func call(
    _ name: String, arguments: [String: Value]?, database: AppDatabase, now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> CallTool.Result {
    let args = arguments ?? [:]
    do {
      switch name {
      case "save_to_engram":
        let request = try decode(SaveRequest.self, from: args)
        let result = try database.saveFromClaude(request, now: now)
        if !result.duplicate { ChangeSignal.post() }
        return try reply(result)

      case "sort_capture":
        let captureID = try string("captureId", in: args)
        let entries = try decode([EntryInput].self, from: args["entries"] ?? [])
        let updates = try decode([ContextUpdateInput].self, from: args["contextUpdates"] ?? [])
        let result = try database.sortCapture(
          captureID, entries: entries, contextUpdates: updates, now: now)
        ChangeSignal.post()
        return try reply(result)

      case "update_project":
        let update = try decode(ContextUpdateInput.self, from: args)
        let result = try database.updateProjectFromClaude(update, now: now)
        ChangeSignal.post()
        return try reply(result)

      case "complete_task":
        let entryID = try string("entryId", in: args)
        let done = args["done"]?.boolValue ?? true
        let result = try database.completeTaskFromClaude(entryID, done: done, now: now)
        ChangeSignal.post()
        return try reply(result)

      case "list_projects":
        let projects = try database.writer.read(AppDatabase.projectSummaries)
        return try reply(
          ProjectList(
            now: localTimestamp(now, in: timeZone), timeZone: timeZone.identifier,
            projects: projects))

      case "get_project_context":
        let slug = try string("slug", in: args)
        guard
          let context = try database.writer.read({ try AppDatabase.projectContext($0, slug: slug) })
        else {
          let slugs = try database.writer.read(AppDatabase.projectSummaries).map(\.slug)
          throw InputErrorMessage(
            "slug: no active project \"\(slug)\". Known slugs: \(slugs.joined(separator: ", ")).")
        }
        return try reply(context)

      case "search_entries":
        let query = try string("query", in: args)
        let kind = try args["kind"]?.stringValue.map { raw -> EntryKind in
          guard let kind = EntryKind(rawValue: raw) else {
            throw InputErrorMessage("kind: use task, idea, note or link.")
          }
          return kind
        }
        let limit = min(max(args["limit"]?.intValue ?? 20, 1), 50)
        let hits = try database.writer.read { db in
          try AppDatabase.search(
            db, query: query, projectSlug: args["projectSlug"]?.stringValue, kind: kind,
            limit: limit)
        }
        return try reply(hits.map { EntryView($0, timeZone: timeZone) })

      case "list_tasks":
        var dueBefore: Date?
        if let raw = args["dueBefore"]?.stringValue {
          guard let date = AppDatabase.parseDueDate(raw, timeZone: timeZone) else {
            throw InputErrorMessage("dueBefore: use ISO 8601, e.g. 2026-11-07.")
          }
          dueBefore = date
        }
        let tasks = try database.writer.read { db in
          try AppDatabase.openTasks(
            db, projectSlug: args["projectSlug"]?.stringValue, dueBefore: dueBefore)
        }
        return try reply(tasks.map { EntryView($0, timeZone: timeZone) })

      case "list_unsorted":
        return try reply(try database.writer.read { try AppDatabase.unsortedThoughts($0) })

      case "write_journal":
        let input = try decode(JournalWriteInput.self, from: args)
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let result = try database.writeJournalFromClaude(input, now: now, calendar: calendar)
        if !result.duplicate { ChangeSignal.post() }
        return try reply(result)

      case "get_journal":
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let range = try AppDatabase.journalRange(
          from: args["from"]?.stringValue, to: args["to"]?.stringValue, now: now,
          calendar: calendar)
        return try reply(
          try database.writer.read { db in
            try AppDatabase.journalExport(
              db, from: range.from, to: range.to, timeZone: timeZone, calendar: calendar)
          })

      default:
        return failure("Unknown tool \"\(name)\".")
      }
    } catch let error as InputError {
      return failure(error.description)
    } catch let error as InputErrorMessage {
      return failure(error.message)
    } catch let error as DecodingError {
      return failure("Invalid arguments: \(describe(error))")
    } catch {
      return failure("Engram failed: \(error.localizedDescription)")
    }
  }

  struct ProjectList: Codable {
    var now: String
    var timeZone: String
    var projects: [ProjectSummary]
  }

  struct InputErrorMessage: Error {
    var message: String
    init(_ message: String) { self.message = message }
  }

  static func decode<T: Decodable>(_ type: T.Type, from args: [String: Value]) throws -> T {
    try decode(type, from: Value.object(args))
  }

  static func decode<T: Decodable>(_ type: T.Type, from value: Value) throws -> T {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
  }

  static func string(_ key: String, in args: [String: Value]) throws -> String {
    guard let value = args[key]?.stringValue, !value.isEmpty else {
      throw InputErrorMessage("\(key): required.")
    }
    return value
  }

  static func reply(_ value: some Encodable) throws -> CallTool.Result {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let text = String(decoding: try encoder.encode(value), as: UTF8.self)
    return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
  }

  static func failure(_ message: String) -> CallTool.Result {
    .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
  }

  static func localTimestamp(_ date: Date, in zone: TimeZone) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = zone
    formatter.formatOptions = [.withInternetDateTime]
    let weekday = date.formatted(
      Date.FormatStyle(timeZone: zone).weekday(.wide).locale(.init(identifier: "en_US")))
    return "\(formatter.string(from: date)) (\(weekday))"
  }

  static func describe(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, let context):
      return "missing \((context.codingPath + [key]).map(\.stringValue).joined(separator: "."))"
    case .typeMismatch(_, let context), .valueNotFound(_, let context),
      .dataCorrupted(let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return "\(path.isEmpty ? "arguments" : path): wrong type"
    @unknown default:
      return "wrong shape"
    }
  }
}
