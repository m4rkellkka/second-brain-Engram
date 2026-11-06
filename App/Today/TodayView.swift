import EngramKit
import SwiftUI

/// The first tab: what happened today and what waits for you.
struct TodayView: View {
  @Environment(AppModel.self) private var model
  @State private var digest = TodayDigest.empty
  @State private var day = Calendar.current.startOfDay(for: Date())
  @State private var loadError: String?

  var body: some View {
    ScrollView {
      ViewThatFits(in: .horizontal) {
        // Side by side from about 850 pt; the ideal width is what
        // ViewThatFits measures, the main column still grows to 700.
        HStack(alignment: .top, spacing: 32) {
          main.frame(minWidth: 400, idealWidth: 440, maxWidth: 700)
          side.frame(width: 290)
        }
        VStack(alignment: .leading, spacing: 24) {
          main
          side
        }
      }
      .padding(.horizontal, 40)
      .padding(.vertical, 32)
      .frame(maxWidth: 1100)
      .frame(maxWidth: .infinity)
    }
    .scrollContentBackground(.hidden)
    // A new day starts a new digest.
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      day = Calendar.current.startOfDay(for: Date())
    }
    .task(id: TodayKey(day: day, changes: model.externalChanges)) {
      guard let database = model.database else { return }
      do {
        for try await value in database.todayUpdates() {
          digest = value
          loadError = nil
        }
      } catch {
        loadError = "Couldn't load today: \(error.localizedDescription)"
      }
    }
  }

  private var isFirstLaunch: Bool {
    digest.totalEntries == 0 && digest.projects.isEmpty && digest.unsorted == 0
  }

  private var main: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        SectionLabel(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
        Text(Self.greeting(for: Date()))
          .font(.geist(30, .semibold))
          .tracking(-0.4)
          .foregroundStyle(Theme.text)
        Text(subtitle).font(.geist(14)).foregroundStyle(Theme.textMuted)
      }

      CaptureBox(prominent: true)

      if let loadError {
        Text(loadError).font(.geist(13)).foregroundStyle(Theme.danger)
      } else if isFirstLaunch {
        WelcomeCard()
      } else {
        TodayFeed(entries: digest.entries)
      }
    }
  }

  private var side: some View {
    VStack(alignment: .leading, spacing: 16) {
      if digest.waiting > 0 { WaitingCard(digest: digest) }
      if !digest.dueSoon.isEmpty { DueSoonCard(tasks: digest.dueSoon) }
      if !digest.projects.isEmpty { ProjectsCard(projects: digest.projects) }
      if digest.totalEntries > 0 {
        BrainCard(projects: digest.projects, total: digest.totalEntries)
      }
    }
  }

  private var subtitle: String {
    let saved = digest.savedByClaude
    let waiting = digest.waiting
    let first =
      saved == 0
      ? (digest.entries.isEmpty ? "Nothing saved yet today" : "\(digest.entries.count) saved today")
      : "Claude saved \(saved) thing\(saved == 1 ? "" : "s") today"
    return waiting == 0 ? first : "\(first) · \(waiting) wait for you"
  }

  static func greeting(for date: Date) -> String {
    switch Calendar.current.component(.hour, from: date) {
    case 5..<12: "Good morning"
    case 12..<18: "Good afternoon"
    case 18..<23: "Good evening"
    default: "Good night"
    }
  }
}

private struct TodayKey: Hashable {
  var day: Date
  var changes: Int
}

/// Today's entries, newest first, as a light list.
private struct TodayFeed: View {
  @Environment(AppModel.self) private var model
  let entries: [InboxItem]
  private let limit = 8

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SectionLabel("Today · \(entries.count)").padding(.bottom, 4)
      if entries.isEmpty {
        Text("Nothing yet. Write a thought above, or tell Claude “save this to Engram”.")
          .font(.geist(13.5))
          .foregroundStyle(Theme.textSubtle)
          .padding(.vertical, 14)
      }
      ForEach(entries.prefix(limit)) { item in
        Button {
          if let project = item.project {
            model.openProject(project.id)
          } else {
            model.section = .inbox
          }
        } label: {
          FeedRow(item: item)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
      }
      if entries.count > limit {
        Button("Show all \(entries.count) in the Inbox →") { model.section = .inbox }
          .buttonStyle(.plain)
          .font(.geist(12.5))
          .foregroundStyle(Theme.accent)
          .padding(.top, 12)
      }
    }
  }
}

private struct FeedRow: View {
  let item: InboxItem

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      Text(item.entry.createdAt, format: .dateTime.hour().minute())
        .font(.geistMono(11))
        .foregroundStyle(Theme.textSubtle)
        .frame(width: 40, alignment: .leading)
      VStack(alignment: .leading, spacing: 4) {
        Text(item.entry.content)
          .font(.geist(14))
          .foregroundStyle(item.entry.doneAt == nil ? Theme.text : Theme.textSubtle)
          .strikethrough(item.entry.doneAt != nil, color: Theme.textSubtle)
          .lineSpacing(2)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
        HStack(spacing: 0) {
          Text(item.entry.kind.rawValue).foregroundStyle(Theme.kindColor(item.entry.kind.rawValue))
          if let project = item.project { Text(" · \(project.name)") }
          if item.capture?.source == .claude { Text(" · from Claude") }
          if item.entry.needsReview { Text(" · not sure") }
        }
        .font(.geist(12))
        .foregroundStyle(Theme.textSubtle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 13)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
  }
}

/// First launch: how to get started.
private struct WelcomeCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Welcome to Engram").font(.geist(18, .semibold)).foregroundStyle(Theme.text)
      Text(
        "Connect Claude Desktop, then say “save this to Engram” in any chat. Claude files what matters into your projects. Or write your first thought above."
      )
      .font(.geist(13.5))
      .foregroundStyle(Theme.textMuted)
      .lineSpacing(3)
      .fixedSize(horizontal: false, vertical: true)
      SettingsLink {
        Text("Connect to Claude Desktop")
      }
      .buttonStyle(AccentButtonStyle())
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassPanel()
  }
}

/// "Not sure" groups and unsorted thoughts.
private struct WaitingCard: View {
  @Environment(AppModel.self) private var model
  let digest: TodayDigest
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel("Waiting for you · \(digest.waiting)", color: Theme.accent)
      if let group = digest.notSure.first {
        let count = group.entries.count
        if let suggestion = group.suggestion {
          Text(
            "\(count) entr\(count == 1 ? "y" : "ies"). Claude suggests a project «\(suggestion)»."
          )
          .font(.geist(13.5))
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
            Button("Create and file \(count)") {
              if let first = group.entries.first {
                error = model.createSuggestedProject(forEntry: first.entry.id)
              }
            }
            .buttonStyle(AccentButtonStyle(height: 30))
            Button("Review") { model.section = .inbox }
              .buttonStyle(QuietButtonStyle(height: 30))
          }
        } else {
          Text("\(count) entr\(count == 1 ? "y" : "ies") Claude wasn't sure where to file.")
            .font(.geist(13.5))
            .foregroundStyle(Theme.text)
          Button("Review") { model.section = .inbox }
            .buttonStyle(QuietButtonStyle(height: 30))
        }
      }
      if digest.unsorted > 0 {
        Text(
          "\(digest.unsorted) typed thought\(digest.unsorted == 1 ? "" : "s") wait for Claude. Ask it to “sort my Engram inbox”."
        )
        .font(.geist(12.5))
        .foregroundStyle(Theme.textMuted)
        .fixedSize(horizontal: false, vertical: true)
      }
      if let error {
        Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassPanel(border: Theme.accent.opacity(0.4), dashed: true)
  }
}

private struct DueSoonCard: View {
  @Environment(AppModel.self) private var model
  let tasks: [InboxItem]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel("Due soon")
      ForEach(tasks) { item in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Button {
            _ = model.setDone(true, entryID: item.entry.id)
          } label: {
            Image(systemName: "circle")
              .font(.system(size: 13))
              .foregroundStyle(Theme.textMuted)
              .frame(width: 18, height: 18)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Mark “\(item.entry.content)” done")
          Text(item.entry.content)
            .font(.geist(13))
            .foregroundStyle(Theme.text)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
          if let due = item.entry.dueAt {
            let label = Self.dueLabel(due)
            Text(label.text)
              .font(.geistMono(11))
              .foregroundStyle(label.urgent ? Theme.kindColor("task") : Theme.textSubtle)
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassPanel()
  }

  /// "overdue", "today", "tomorrow" or a weekday.
  static func dueLabel(_ due: Date, now: Date = Date()) -> (text: String, urgent: Bool) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let dueDay = calendar.startOfDay(for: due)
    let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
    switch days {
    case ..<0: return ("overdue", true)
    case 0: return ("today", true)
    case 1: return ("tomorrow", true)
    default: return (due.formatted(.dateTime.weekday(.abbreviated)), false)
    }
  }
}

private struct ProjectsCard: View {
  @Environment(AppModel.self) private var model
  let projects: [TodayDigest.ProjectActivity]

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      SectionLabel("Projects").padding(.bottom, 4)
      ForEach(projects.prefix(5)) { row in
        Button {
          model.openProject(row.project.id)
        } label: {
          HStack(spacing: 10) {
            Circle().fill(Color(hexString: row.project.color)).frame(width: 8, height: 8)
            Text(row.project.name).font(.geist(13)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            if row.addedToday > 0 {
              Text("+\(row.addedToday)").font(.geistMono(11)).foregroundStyle(Theme.accent)
            } else {
              Text("\(row.entryCount)").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
            }
          }
          .frame(height: 28)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
      }
      if projects.count > 5 {
        Button("All projects →") { model.section = .projects }
          .buttonStyle(.plain)
          .font(.geist(12))
          .foregroundStyle(Theme.accent)
          .padding(.top, 4)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassPanel()
  }
}

/// A small, still picture of the graph that opens the Brain.
private struct BrainCard: View {
  @Environment(AppModel.self) private var model
  let projects: [TodayDigest.ProjectActivity]
  let total: Int

  var body: some View {
    Button {
      model.section = .brain
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        SectionLabel("Brain · \(total) entries")
        MiniGraph(projects: Array(projects.prefix(5)))
          .frame(height: 96)
        Text("Open the Brain →").font(.geist(12)).foregroundStyle(Theme.accent)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glassPanel()
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .accessibilityLabel("Open the Brain")
  }
}

/// Each project as a hub with a few satellites, sized by its entries.
/// Drawn with Canvas (no Metal), so Today opens instantly.
private struct MiniGraph: View {
  let projects: [TodayDigest.ProjectActivity]

  var body: some View {
    Canvas { context, size in
      guard !projects.isEmpty else { return }
      let largest = Double(projects.map(\.entryCount).max() ?? 1)
      let step = size.width / Double(projects.count)
      for (i, row) in projects.enumerated() {
        let color = Color(hexString: row.project.color)
        let center = CGPoint(
          x: step * (Double(i) + 0.5), y: size.height / 2 + (i % 2 == 0 ? -8 : 8))
        let weight = (Double(max(row.entryCount, 1)) / max(largest, 1)).squareRoot()
        let satellites = min(max(row.entryCount, 1), 7)
        let reach = 14 + 20 * weight
        // FNV-1a of the id: stable across launches, unlike `hashValue`.
        var seed = row.project.id.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) {
          ($0 ^ UInt64($1)) &* 0x100_0000_01b3
        }
        for k in 0..<satellites {
          seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
          let angle = Double(k) / Double(satellites) * 2 * .pi + Double(seed % 100) / 100
          let distance = reach * (0.6 + 0.4 * Double((seed >> 8) % 100) / 100)
          let point = CGPoint(
            x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance * 0.8)
          var line = Path()
          line.move(to: center)
          line.addLine(to: point)
          context.stroke(line, with: .color(.white.opacity(0.1)), lineWidth: 1)
          context.fill(
            Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
            with: .color(color))
        }
        let hub = 4 + 4 * weight
        context.fill(
          Path(
            ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)
          ),
          with: .color(color.opacity(0.95)))
      }
    }
    .accessibilityHidden(true)
  }
}

#Preview("Today") {
  TodayView()
    .environment(AppModel.preview())
    .frame(width: 1040, height: 720)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
