import EngramKit
import SwiftUI

/// The panel beside the graph: the focused project, or the clicked entry.
struct BrainSidePanel: View {
  @Environment(AppModel.self) private var model
  let selection: BrainSelection
  let graph: GraphSnapshot
  let close: () -> Void
  @State private var page: ProjectPage?

  private var node: GraphSnapshot.Node? {
    guard case .node(let id) = selection else { return nil }
    return graph.nodes.first { $0.id == id }
  }

  private var projectID: String? {
    switch selection {
    case .project(let id): id
    case .node: node?.projectID
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Spacer()
          Button(action: close) {
            Image(systemName: "xmark")
              .foregroundStyle(Theme.textMuted)
              .frame(width: 28, height: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .focusEffectDisabled()
          .accessibilityLabel("Close panel")
        }
        .padding(.bottom, -12)

        if let node, let day = node.journalDay {
          JournalDayCard(node: node)
          Button {
            model.openJournal(day == JournalDate.key(Date()) ? nil : day)
          } label: {
            Text("Open in Journal").frame(maxWidth: .infinity)
          }
          .buttonStyle(AccentButtonStyle(height: 34))
          .focusEffectDisabled()
        } else if let node {
          EntryCard(node: node)
        }

        if let page {
          ProjectSummary(page: page)
          Button {
            model.openProject(page.project.id)
          } label: {
            Text("Open project").frame(maxWidth: .infinity)
          }
          .buttonStyle(AccentButtonStyle(height: 34))
          .focusEffectDisabled()
        } else if projectID == nil, node?.isJournal != true {
          Text("Not filed in a project yet. Pick one in the Inbox.")
            .font(.geist(12.5))
            .foregroundStyle(Theme.textSubtle)
          SmallButton(title: "Open Inbox", symbol: "tray") { model.section = .inbox }
        }
      }
      .padding(22)
    }
    .scrollContentBackground(.hidden)
    .glassPanel(radius: 20)
    .padding(16)
    .task(id: PanelKey(project: projectID, changes: model.externalChanges)) {
      guard let projectID, let database = model.database else {
        page = nil
        return
      }
      do {
        for try await value in database.projectPageUpdates(projectID) { page = value }
      } catch {}
    }
  }
}

private struct PanelKey: Hashable {
  var project: String?
  var changes: Int
}

private struct EntryCard: View {
  let node: GraphSnapshot.Node

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        KindBadge(kind: node.kind)
        if node.done {
          Label("done", systemImage: "checkmark").font(.geist(11.5)).foregroundStyle(
            Theme.textSubtle)
        }
        Spacer()
        Text(node.createdAt, format: .dateTime.day().month(.abbreviated))
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
      }
      Text(node.content)
        .font(.geist(14))
        .foregroundStyle(Theme.text)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
  }
}

private struct JournalDayCard: View {
  let node: GraphSnapshot.Node

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      JournalBadge(date: node.createdAt)
      Text(node.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .font(.geist(18, .semibold))
        .foregroundStyle(Theme.text)
      Text(node.content)
        .font(.geist(14))
        .foregroundStyle(Theme.textMuted)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
  }
}

private struct ProjectSummary: View {
  let page: ProjectPage

  var body: some View {
    let ideas = page.kindCounts[.idea, default: 0]
    let notes = page.kindCounts[.note, default: 0] + page.kindCounts[.link, default: 0]
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
          Circle().fill(Color(hexString: page.project.color)).frame(width: 10, height: 10)
          Text(page.project.name).font(.geist(20, .semibold)).foregroundStyle(Theme.text)
        }
        if let status = page.project.status {
          Text(status)
            .font(.geistMono(11.5))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .overlay(Capsule().stroke(Theme.borderStrong))
        }
      }

      HStack(spacing: 8) {
        Stat(value: ideas, label: "ideas")
        Stat(value: page.openTasks.count, label: "open tasks")
        Stat(value: notes, label: "notes")
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          SectionLabel("Live context")
          Spacer()
          Text(page.project.summarySource == .user ? "edited by you" : "by Claude")
            .font(.geist(11.5))
            .foregroundStyle(Theme.textSubtle)
        }
        Text(page.project.summary ?? "No summary yet.")
          .font(.geist(13.5))
          .foregroundStyle(page.project.summary == nil ? Theme.textSubtle : Theme.text)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      let recent = (page.recentEntries + page.openTasks)
        .sorted { $0.entry.createdAt > $1.entry.createdAt }.prefix(5)
      if !recent.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          SectionLabel("Recent")
          ForEach(Array(recent)) { item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Circle().fill(Theme.kindColor(item.entry.kind.rawValue)).frame(width: 5, height: 5)
              Text(item.entry.content)
                .font(.geist(12.5))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
            }
          }
        }
      }
    }
  }
}

private struct Stat: View {
  let value: Int
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(value)").font(.geist(18, .semibold)).foregroundStyle(Theme.text)
      Text(label).font(.geist(11.5)).foregroundStyle(Theme.textSubtle)
        .lineLimit(1).minimumScaleFactor(0.8)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
  }
}
