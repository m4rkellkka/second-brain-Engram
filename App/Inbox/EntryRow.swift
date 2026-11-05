import EngramKit
import SwiftUI

struct EntryRow: View {
  @Environment(AppModel.self) private var model
  let item: InboxItem
  let projects: [Project]
  @State private var error: String?

  private var entry: Entry { item.entry }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        KindMenu(kind: entry.kind) { error = model.setKind($0, forEntry: entry.id) }
        SourceLabel(capture: item.capture)
        Spacer()
        Text(entry.createdAt, format: .relative(presentation: .named))
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
      }

      Text(entry.content)
        .font(.geist(14.5))
        .foregroundStyle(Theme.text)
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)

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

      if entry.needsReview {
        NotSureBar(entry: entry) { error = $0 }
      }

      HStack(spacing: 8) {
        ProjectPicker(entryID: entry.id, current: item.project, projects: projects)
        if let error {
          Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
        }
      }
    }
    .padding(16)
    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .stroke(entry.needsReview ? Theme.kindColor("task").opacity(0.45) : Theme.border))
  }
}

/// "Not sure" actions: accept as is, or create the project Claude proposed.
private struct NotSureBar: View {
  @Environment(AppModel.self) private var model
  let entry: Entry
  let report: (String?) -> Void

  var body: some View {
    HStack(spacing: 8) {
      Label("Not sure", systemImage: "questionmark.circle")
        .font(.geist(12, .medium))
        .foregroundStyle(Theme.kindColor("task"))
      Spacer()
      if let suggestion = entry.suggestedProject {
        SmallButton(title: "Create “\(suggestion)”", symbol: "plus") {
          report(model.createSuggestedProject(forEntry: entry.id))
        }
      }
      SmallButton(title: "Looks right", symbol: "checkmark") {
        report(model.confirm(entry.id))
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 36)
    .background(
      RoundedRectangle(cornerRadius: Theme.controlRadius).fill(
        Theme.kindColor("task").opacity(0.08)))
  }
}

struct KindBadge: View {
  let kind: EntryKind

  var body: some View {
    let color = Theme.kindColor(kind.rawValue)
    Text(kind.rawValue.uppercased())
      .font(.geistMono(10.5, .medium))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .frame(height: 20)
      .background(Capsule().fill(color.opacity(0.12)))
  }
}

/// The kind badge, clickable to fix the kind.
private struct KindMenu: View {
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
      KindBadge(kind: kind)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel("Kind: \(kind.rawValue)")
  }
}

private struct SourceLabel: View {
  let capture: Capture?

  var body: some View {
    if let capture {
      switch (capture.source, capture.status) {
      case (.claude, _):
        Label("Claude", systemImage: "sparkle")
          .font(.geist(11.5))
          .foregroundStyle(Theme.textSubtle)
          .help(capture.conversationRef ?? "Saved from a Claude conversation")
      case (.typed, .unsorted):
        Text("unsorted").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
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
      .frame(height: 26)
      .background(Capsule().fill(Theme.surface2))
  }
}

struct SmallButton: View {
  let title: String
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.geist(12, .medium))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(Theme.surface2))
        .overlay(Capsule().stroke(Theme.borderStrong))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}
