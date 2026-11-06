import EngramKit
import SwiftUI

/// One Inbox line: kind, text, project and when it came in. Kind and
/// project are menus, so a wrong guess from Claude is one click to fix.
struct EntryRow: View {
  @Environment(AppModel.self) private var model
  let item: InboxItem
  let projects: [Project]
  @State private var error: String?

  private var entry: Entry { item.entry }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      KindMenu(kind: entry.kind) { error = model.setKind($0, forEntry: entry.id) }
        .frame(width: 60, alignment: .leading)

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .top, spacing: 4) {
          if entry.kind == .task { TaskCheckbox(item: item).padding(.top, -4) }
          Text(entry.content)
            .font(.geist(14))
            .foregroundStyle(entry.doneAt == nil ? Theme.text : Theme.textSubtle)
            .strikethrough(entry.doneAt != nil, color: Theme.textSubtle)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        if entry.dueAt != nil || entry.url != nil {
          HStack(spacing: 8) {
            if let due = entry.dueAt {
              Chip(symbol: "calendar", text: due.formatted(date: .abbreviated, time: .omitted))
            }
            if let raw = entry.url, let url = URL(string: raw) {
              Link(destination: url) {
                Chip(symbol: "link", text: url.host() ?? raw)
              }
              .buttonStyle(.plain)
            }
          }
        }
        if let error {
          Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
        }
      }

      ProjectPicker(entryID: entry.id, current: item.project, projects: projects)

      HStack(spacing: 4) {
        SourceLabel(capture: item.capture)
        Text(entry.createdAt, format: .dateTime.hour().minute())
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
      }
      .frame(width: 64, alignment: .trailing)
      .frame(minHeight: 28)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 4)
    .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
  }
}

/// The kind in its color, clickable to fix it.
struct KindMenu: View {
  let kind: EntryKind
  let change: (EntryKind) -> Void

  var body: some View {
    Menu {
      ForEach(EntryKind.allCases, id: \.self) { option in
        Button {
          change(option)
        } label: {
          if option == kind {
            Label(option.rawValue.capitalized, systemImage: "checkmark")
          } else {
            Text(option.rawValue.capitalized)
          }
        }
      }
    } label: {
      Text(kind.rawValue)
        .font(.geistMono(11, .medium))
        .foregroundStyle(Theme.kindColor(kind.rawValue))
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Change the kind")
    .accessibilityLabel("Kind: \(kind.rawValue)")
  }
}

/// ✦ for what Claude saved; "unsorted" for typed thoughts Claude hasn't seen.
private struct SourceLabel: View {
  let capture: Capture?

  var body: some View {
    if let capture {
      switch (capture.source, capture.status) {
      case (.claude, _):
        Text("✦")
          .font(.geist(11))
          .foregroundStyle(Theme.textSubtle)
          .help(capture.conversationRef.map { "From Claude: \($0)" } ?? "Saved by Claude")
          .accessibilityLabel("Saved by Claude")
      case (.typed, .unsorted):
        Text("unsorted")
          .font(.geistMono(10.5))
          .foregroundStyle(Theme.textSubtle)
          .help("Ask Claude to “sort my Engram inbox”")
      case (.typed, .sorted):
        EmptyView()
      }
    }
  }
}

private struct Chip: View {
  let symbol: String
  let text: String

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.geist(12))
      .foregroundStyle(Theme.textMuted)
      .padding(.horizontal, 10)
      .frame(height: 24)
      .overlay(Capsule().strokeBorder(Theme.borderStrong.opacity(0.7)))
  }
}
