import EngramKit
import SwiftUI

struct InboxView: View {
  @Environment(AppModel.self) private var model
  @State private var filter = InboxFilter.all
  @State private var items: [InboxItem] = []
  @State private var projects: [Project] = []
  @State private var loadError: String?

  private var notSure: [InboxItem] { items.filter(\.entry.needsReview) }

  /// The feed below the "not sure" cards: those entries are already in a
  /// card when everything shows, so they aren't listed twice.
  private var feed: [InboxItem] {
    switch filter {
    case .all: items.filter { !$0.entry.needsReview }
    case .kind: items
    case .notSure: []
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header and capture stay put; only the feed scrolls, so focusing the
      // capture field never scrolls the page.
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Inbox").font(.geist(26, .semibold)).tracking(-0.4).foregroundStyle(Theme.text)
          Text(subtitle).font(.geist(13)).foregroundStyle(Theme.textSubtle)
        }
        FilterBar(selection: $filter, notSureCount: notSure.count)
        CaptureBox(compact: true)
      }
      .padding(.horizontal, 32)
      .padding(.top, 28)
      .padding(.bottom, 14)
      .frame(maxWidth: 860, alignment: .leading)
      .frame(maxWidth: .infinity)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let loadError {
            Text(loadError).font(.geist(13)).foregroundStyle(Theme.danger)
          } else if items.isEmpty {
            Text(
              filter == .all
                ? "All sorted. New thoughts and Claude's saves show up here." : "No entries."
            )
            .font(.geist(13.5))
            .foregroundStyle(Theme.textSubtle)
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
          } else {
            // A kind filter shows a plain list; otherwise "not sure" comes first.
            if filter.kind == nil {
              ForEach(NotSureGroup.make(notSure)) { group in
                NotSureCard(group: group, projects: projects)
              }
            }
            DayFeed(items: feed, projects: projects)
            if filter == .all {
              Text("✦ saved by Claude · click a kind or a project to fix it")
                .font(.geist(12))
                .foregroundStyle(Theme.textSubtle)
            }
          }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
        .frame(maxWidth: 860, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      .scrollContentBackground(.hidden)
    }
    // Restart the observations when the connector wrote from its own process.
    .task(id: InboxKey(kind: filter.kind, changes: model.externalChanges)) {
      await observeInbox()
    }
    .task(id: model.externalChanges) { await observeProjects() }
  }

  private var subtitle: String {
    let unsorted = items.filter { $0.capture?.source == .typed && $0.capture?.status == .unsorted }
    var parts = ["\(items.count) latest"]
    if !notSure.isEmpty { parts.append("\(notSure.count) not sure") }
    if !unsorted.isEmpty { parts.append("\(unsorted.count) unsorted") }
    return parts.joined(separator: " · ")
  }

  private func observeInbox() async {
    guard let database = model.database else { return }
    do {
      for try await rows in database.inboxUpdates(kind: filter.kind) {
        items = rows
        loadError = nil
      }
    } catch {
      loadError = "Couldn't load the Inbox: \(error.localizedDescription)"
    }
  }

  private func observeProjects() async {
    guard let database = model.database else { return }
    do {
      for try await rows in database.activeProjectUpdates() { projects = rows }
    } catch {
      loadError = "Couldn't load projects: \(error.localizedDescription)"
    }
  }
}

enum InboxFilter: Hashable {
  case all
  case kind(EntryKind)
  case notSure

  var kind: EntryKind? {
    if case .kind(let kind) = self { return kind }
    return nil
  }
}

private struct InboxKey: Hashable {
  var kind: EntryKind?
  var changes: Int
}

private struct FilterBar: View {
  @Binding var selection: InboxFilter
  let notSureCount: Int

  private let kinds: [(title: String, filter: InboxFilter)] = [
    ("All", .all), ("Ideas", .kind(.idea)), ("Tasks", .kind(.task)), ("Notes", .kind(.note)),
    ("Links", .kind(.link)),
  ]

  var body: some View {
    HStack(spacing: 6) {
      ForEach(kinds, id: \.title) { option in
        FilterChip(title: option.title, isSelected: option.filter == selection) {
          selection = option.filter
        }
      }
      if notSureCount > 0 || selection == .notSure {
        FilterChip(
          title: "Not sure \(notSureCount)", isSelected: selection == .notSure, dashed: true
        ) { selection = .notSure }
      }
    }
  }
}

/// "Not sure" entries that share the project Claude suggested.
private struct NotSureGroup: Identifiable {
  var suggestion: String?
  var items: [InboxItem]
  var id: String { suggestion?.lowercased() ?? "" }

  static func make(_ items: [InboxItem]) -> [NotSureGroup] {
    var groups: [NotSureGroup] = []
    for item in items {
      let raw = item.entry.suggestedProject?.trimmingCharacters(in: .whitespaces)
      let suggestion = raw?.isEmpty == false ? raw : nil
      if let index = groups.firstIndex(where: { $0.id == (suggestion?.lowercased() ?? "") }) {
        groups[index].items.append(item)
      } else {
        groups.append(NotSureGroup(suggestion: suggestion, items: [item]))
      }
    }
    return groups
  }
}

private struct NotSureCard: View {
  @Environment(AppModel.self) private var model
  let group: NotSureGroup
  let projects: [Project]
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 12) {
        SectionLabel("Not sure · \(group.items.count)", color: Theme.accent)
        Text(
          group.suggestion.map { "Claude suggests a new project «\($0)»" }
            ?? "Claude wasn't sure where these go"
        )
        .font(.geist(13.5, .medium))
        .foregroundStyle(Theme.text)
        Spacer(minLength: 0)
        if let suggestion = group.suggestion, let first = group.items.first {
          Button("Create «\(suggestion)» and file \(group.items.count)") {
            error = model.createSuggestedProject(forEntry: first.entry.id)
          }
          .buttonStyle(AccentButtonStyle(height: 30))
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        ForEach(group.items) { item in
          HStack(spacing: 10) {
            Text(item.entry.kind.rawValue)
              .font(.geistMono(11, .medium))
              .foregroundStyle(Theme.kindColor(item.entry.kind.rawValue))
              .frame(width: 40, alignment: .leading)
            Text(item.entry.content)
              .font(.geist(13.5))
              .foregroundStyle(Theme.textMuted)
              .lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
            ProjectPicker(entryID: item.entry.id, current: item.project, projects: projects)
            SmallButton(title: "Looks right", symbol: "checkmark") {
              error = model.confirm(item.entry.id)
            }
            .help("Keep it as it is")
          }
        }
      }
      if let error {
        Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
      }
    }
    .padding(16)
    .glassPanel(border: Theme.accent.opacity(0.4), dashed: true)
  }
}

/// Entries under "Today", "Yesterday" or their date.
private struct DayFeed: View {
  let items: [InboxItem]
  let projects: [Project]

  var body: some View {
    let days = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.entry.createdAt) }
    VStack(alignment: .leading, spacing: 18) {
      ForEach(days.keys.sorted(by: >), id: \.self) { day in
        VStack(alignment: .leading, spacing: 0) {
          SectionLabel(Self.title(for: day)).padding(.bottom, 2)
          ForEach(days[day] ?? []) { item in
            EntryRow(item: item, projects: projects)
          }
        }
      }
    }
  }

  static func title(for day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }
}

#Preview("Inbox") {
  InboxView()
    .environment(AppModel.preview())
    .frame(width: 900, height: 700)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("Inbox, empty") {
  InboxView()
    .environment(AppModel.preview(withSamples: false))
    .frame(width: 900, height: 500)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
