import EngramKit
import SwiftUI

/// The Journal tab: days on the left, the open day's page on the right.
struct JournalView: View {
  @Environment(AppModel.self) private var model
  @State private var days: [JournalListItem] = []
  @State private var today = JournalDate.key(Date())

  private var selected: String { model.openJournalDay ?? today }

  var body: some View {
    HStack(spacing: 0) {
      DayList(days: days, today: today, selected: selected)
        .frame(width: 280)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
      JournalDayView(day: selected, today: today)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      today = JournalDate.key(Date())
    }
    .task(id: ListKey(today: today, changes: model.externalChanges)) {
      guard let database = model.database else { return }
      do {
        for try await value in database.journalDaysUpdates() { days = value }
      } catch {}
    }
  }
}

private struct ListKey: Hashable {
  var today: String
  var changes: Int
}

/// Days grouped by month, newest first. "Go to date…" in the ⋯ menu opens
/// a day that has nothing in it yet, for writing about it later.
private struct DayList: View {
  @Environment(AppModel.self) private var model
  let days: [JournalListItem]
  let today: String
  let selected: String
  @State private var pickingDate = false
  @State private var pickedDate = Date()

  private var months: [(title: String, days: [JournalListItem])] {
    var groups: [(title: String, days: [JournalListItem])] = []
    for day in days {
      let title = day.date.formatted(.dateTime.month(.wide).year())
      if groups.last?.title == title {
        groups[groups.count - 1].days.append(day)
      } else {
        groups.append((title, [day]))
      }
    }
    return groups
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Journal").font(.geist(16, .semibold)).foregroundStyle(Theme.text)
        Spacer()
        if selected != today {
          Button("Today") { model.openJournalDay = nil }
            .buttonStyle(QuietButtonStyle(height: 28))
            .focusEffectDisabled()
        }
        Menu {
          Button("Go to date…") {
            pickedDate = JournalDate.start(of: selected) ?? Date()
            pickingDate = true
          }
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textMuted)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
        .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
          DatePicker(
            "Day", selection: $pickedDate, in: ...Date(), displayedComponents: .date
          )
          .datePickerStyle(.graphical)
          .labelsHidden()
          .padding(12)
          .onChange(of: pickedDate) {
            let key = JournalDate.key(pickedDate)
            model.openJournalDay = key == today ? nil : key
            pickingDate = false
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 22)
      .padding(.bottom, 10)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(months, id: \.title) { month in
            SectionLabel(month.title)
              .padding(.horizontal, 12)
              .padding(.top, 14)
              .padding(.bottom, 4)
            ForEach(month.days) { day in
              DayRow(day: day, isToday: day.day == today, isSelected: day.day == selected) {
                model.openJournalDay = day.day == today ? nil : day.day
              }
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 20)
      }
      .scrollContentBackground(.hidden)
    }
  }
}

private struct DayRow: View {
  let day: JournalListItem
  let isToday: Bool
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated).day()))
            .font(.geist(13, .medium))
            .foregroundStyle(Theme.text)
          Spacer()
          Text(status)
            .font(.geistMono(11))
            .foregroundStyle(isSelected ? Theme.accent : Theme.textSubtle)
        }
        if let preview = day.preview {
          Text(preview)
            .font(.geist(12))
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(isSelected ? Theme.accent.opacity(0.1) : .clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(isSelected ? Theme.accent.opacity(0.3) : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var status: String {
    if day.saved > 0 { return "\(day.saved) saved" }
    return day.preview == nil ? "no entry yet" : ""
  }
}

/// One day: its paragraphs, a field for a new one, and what happened.
private struct JournalDayView: View {
  @Environment(AppModel.self) private var model
  let day: String
  let today: String
  @State private var page: JournalPage?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        if let page, page.day == day {
          Header(page: page)
          Paper(page: page, isToday: day == today)
          OnThisDay(page: page)
        }
      }
      .padding(.horizontal, 48)
      .padding(.vertical, 32)
      .frame(maxWidth: 860, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollContentBackground(.hidden)
    .task(id: PageKey(day: day, changes: model.externalChanges)) {
      guard let database = model.database else { return }
      do {
        for try await value in database.journalPageUpdates(day) { page = value }
      } catch {}
    }
  }
}

private struct PageKey: Hashable {
  var day: String
  var changes: Int
}

private struct Header: View {
  let page: JournalPage

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionLabel("Journal")
      Text(page.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .font(.geist(28, .semibold))
        .tracking(-0.5)
        .foregroundStyle(Theme.text)
      Text(byline).font(.geist(12)).foregroundStyle(Theme.textSubtle)
    }
  }

  /// "written with Claude · edited by you at 23:40".
  private var byline: String {
    let paragraphs = page.paragraphs
    guard !paragraphs.isEmpty else { return "Nothing written yet" }
    let withClaude = paragraphs.contains { $0.author == .claude }
    let touches = paragraphs.compactMap { paragraph -> Date? in
      paragraph.editedAt ?? (paragraph.author == .user ? paragraph.createdAt : nil)
    }
    let first = withClaude ? "written with Claude" : "written by you"
    guard let last = touches.max() else { return first }
    let time = last.formatted(.dateTime.hour().minute())
    return withClaude ? "\(first) · edited by you at \(time)" : "\(first) · last at \(time)"
  }
}

/// The day's text on a glass sheet. Click a paragraph to edit it.
private struct Paper: View {
  @Environment(AppModel.self) private var model
  let page: JournalPage
  let isToday: Bool
  @State private var editing: String?
  @State private var draft = ""
  @State private var newText = ""
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      ForEach(page.paragraphs) { paragraph in
        VStack(alignment: .leading, spacing: 4) {
          Text(label(for: paragraph))
            .font(.geistMono(11))
            .foregroundStyle(Theme.textSubtle)
          if editing == paragraph.id {
            editor(text: $draft, placeholder: "Clear it to remove the paragraph") {
              save(paragraph)
            } cancel: {
              editing = nil
            }
            Text("↵ save   ⇧↵ new line   esc cancel")
              .font(.geistMono(11))
              .foregroundStyle(Theme.textSubtle)
          } else {
            Text(paragraph.text)
              .font(.geist(15))
              .foregroundStyle(Theme.text)
              .lineSpacing(6)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
              .onTapGesture { startEditing(paragraph) }
              .help("Click to edit")
              .contextMenu {
                Button("Edit") { startEditing(paragraph) }
                Button("Delete", role: .destructive) {
                  error = model.change { try $0.deleteJournalParagraph(paragraph.id) }
                }
              }
          }
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        editor(text: $newText, placeholder: placeholder, submit: add, cancel: nil)
        if let error {
          Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
        } else if !newText.isEmpty {
          Text("↵ add   ⇧↵ new line")
            .font(.geistMono(11))
            .foregroundStyle(Theme.textSubtle)
        }
      }
      .padding(.top, page.paragraphs.isEmpty ? 0 : 4)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassPanel(border: Theme.border.opacity(1.4))
    .onChange(of: page.day) {
      editing = nil
      newText = ""
      error = nil
    }
  }

  private var placeholder: String {
    page.paragraphs.isEmpty && isToday
      ? "Tell Claude “write to my journal how the day went”, or start typing here."
      : "Add to this day…"
  }

  /// "19:10 · from Claude", or "7 Nov · you · added later" for a paragraph
  /// written on a later day: said, but quietly.
  private func label(for paragraph: JournalParagraph) -> String {
    var parts = [paragraph.createdAt.formatted(.dateTime.hour().minute())]
    parts.append(paragraph.author == .claude ? "from Claude" : "you")
    if paragraph.author == .claude, paragraph.editedAt != nil { parts.append("edited by you") }
    if JournalDate.key(paragraph.createdAt) != paragraph.day {
      parts[0] = paragraph.createdAt.formatted(.dateTime.day().month(.abbreviated))
      parts.append("added later")
    }
    return parts.joined(separator: " · ")
  }

  private func editor(
    text: Binding<String>, placeholder: String, submit: @escaping () -> Void,
    cancel: (() -> Void)?
  ) -> some View {
    ZStack(alignment: .topLeading) {
      if text.wrappedValue.isEmpty {
        Text(placeholder)
          .font(.geist(15))
          .foregroundStyle(Theme.textSubtle)
          .padding(.top, 2)
          .allowsHitTesting(false)
      }
      // Only an edit takes focus; the "add" field waits for a click.
      ThoughtEditor(
        text: text, focusToken: 0, onSubmit: submit, onCancel: cancel,
        focusOnAppear: cancel != nil
      )
      .accessibilityLabel(cancel == nil ? "New journal paragraph" : "Edit paragraph")
    }
    .frame(height: Self.editorHeight(for: text.wrappedValue))
  }

  /// Grows with the text, about 70 characters a line, up to ten lines.
  static func editorHeight(for text: String) -> CGFloat {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { max(1, Int((Double($0.count) / 70).rounded(.up))) }
      .reduce(0, +)
    return CGFloat(min(max(lines, 1), 10)) * 25 + 4
  }

  private func startEditing(_ paragraph: JournalParagraph) {
    draft = paragraph.text
    editing = paragraph.id
    error = nil
  }

  private func save(_ paragraph: JournalParagraph) {
    error = model.change { try $0.editJournalParagraph(paragraph.id, text: draft) }
    if error == nil { editing = nil }
  }

  private func add() {
    guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    error = model.change { try $0.addJournalParagraph(newText, day: page.day) }
    if error == nil { newText = "" }
  }
}

/// What was saved and finished that day.
private struct OnThisDay: View {
  @Environment(AppModel.self) private var model
  let page: JournalPage
  @State private var showAll = false
  private let limit = 6

  private var items: [(item: InboxItem, done: Bool)] {
    let doneIDs = Set(page.done.map(\.id))
    return page.entries.filter { !doneIDs.contains($0.id) }.map { ($0, false) }
      + page.done.map { ($0, true) }
  }

  var body: some View {
    let items = items
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        SectionLabel("On this day · \(page.entries.count) saved · \(page.done.count) done")
        LazyVGrid(
          // Top-aligned, so cards of different heights still line up.
          columns: [
            GridItem(.flexible(), spacing: 10, alignment: .top),
            GridItem(.flexible(), spacing: 10, alignment: .top),
          ],
          alignment: .leading, spacing: 10
        ) {
          ForEach(Array(items.prefix(showAll ? items.count : limit)), id: \.item.id) { row in
            Button {
              if let project = row.item.project {
                model.openProject(project.id)
              } else {
                model.section = .inbox
              }
            } label: {
              DayEntryCard(item: row.item, done: row.done)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
          }
        }
        if items.count > limit {
          Button(showAll ? "Show less" : "Show all \(items.count) →") { showAll.toggle() }
            .buttonStyle(.plain)
            .font(.geist(12))
            .foregroundStyle(Theme.accent)
        }
      }
      .onChange(of: page.day) { showAll = false }
    }
  }
}

private struct DayEntryCard: View {
  let item: InboxItem
  let done: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 0) {
        Text(done ? "done" : item.entry.kind.rawValue)
          .foregroundStyle(Theme.kindColor(done ? "task" : item.entry.kind.rawValue))
        if let project = item.project { Text(" · \(project.name)") }
        if !done {
          Text(" · " + item.entry.createdAt.formatted(.dateTime.hour().minute()))
        }
      }
      .font(.geist(12))
      .foregroundStyle(Theme.textSubtle)
      Text(item.entry.content)
        .font(.geist(13))
        .foregroundStyle(done ? Theme.textMuted : Theme.text)
        .strikethrough(done, color: Theme.textSubtle)
        .lineSpacing(2)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
    .quietCard(radius: 14)
    .contentShape(Rectangle())
  }
}

#Preview("Journal") {
  JournalView()
    .environment(AppModel.preview())
    .frame(width: 1040, height: 720)
    .preferredColorScheme(.dark)
}
