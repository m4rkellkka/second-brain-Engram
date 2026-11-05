import EngramKit
import SwiftUI

struct ProjectsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if let projectID = model.openProjectID {
      ProjectPageView(projectID: projectID)
    } else {
      ProjectsListView()
    }
  }
}

private struct ProjectsListView: View {
  @Environment(AppModel.self) private var model
  @State private var rows: [ProjectOverview] = []
  @State private var isCreating = false
  @State private var showArchived = false

  private var active: [ProjectOverview] { rows.filter { $0.project.archivedAt == nil } }
  private var archived: [ProjectOverview] { rows.filter { $0.project.archivedAt != nil } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Projects").font(.geist(24, .semibold)).foregroundStyle(Theme.text)
            Text("Each page keeps itself up to date from what you save with Claude.")
              .font(.geist(13))
              .foregroundStyle(Theme.textMuted)
          }
          Spacer()
          SmallButton(title: "New project", symbol: "plus") { isCreating = true }
            .popover(isPresented: $isCreating, arrowEdge: .bottom) {
              NewProjectForm { name in
                let message = model.createProject(named: name)
                if message == nil { isCreating = false }
                return message
              }
            }
        }

        if active.isEmpty {
          Text("No projects yet. Create one, or confirm one Claude suggests in the Inbox.")
            .font(.geist(13.5))
            .foregroundStyle(Theme.textSubtle)
            .padding(.top, 24)
        }
        LazyVStack(spacing: 8) {
          ForEach(active) { row in ProjectRow(row: row) }
        }

        if !archived.isEmpty {
          DisclosureGroup(isExpanded: $showArchived) {
            LazyVStack(spacing: 8) {
              ForEach(archived) { row in ProjectRow(row: row) }
            }
            .padding(.top, 8)
          } label: {
            Text("Archived (\(archived.count))").font(.geist(13, .medium))
              .foregroundStyle(Theme.textMuted)
          }
        }
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 28)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
    .scrollContentBackground(.hidden)
    .task(id: model.externalChanges) {
      guard let database = model.database else { return }
      do {
        for try await value in database.projectOverviewUpdates() { rows = value }
      } catch {}
    }
  }
}

private struct ProjectRow: View {
  @Environment(AppModel.self) private var model
  let row: ProjectOverview

  var body: some View {
    Button {
      model.openProject(row.project.id)
    } label: {
      HStack(spacing: 14) {
        Circle().fill(Color(hexString: row.project.color)).frame(width: 10, height: 10)
        VStack(alignment: .leading, spacing: 3) {
          Text(row.project.name).font(.geist(15, .medium)).foregroundStyle(Theme.text)
          if let summary = row.project.summary {
            Text(summary).font(.geist(12.5)).foregroundStyle(Theme.textMuted).lineLimit(1)
          }
        }
        Spacer()
        if let status = row.project.status {
          Text(status).font(.geist(12)).foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 9).frame(height: 22)
            .background(Capsule().fill(Theme.surface2))
        }
        VStack(alignment: .trailing, spacing: 3) {
          Text("\(row.openTasks) open · \(row.entryCount) entries")
            .font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
          if let activity = row.lastActivity {
            Text(activity, format: .relative(presentation: .named))
              .font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
          }
        }
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 60)
      .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
      .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

#Preview("Projects") {
  ProjectsView()
    .environment(AppModel.preview())
    .frame(width: 800, height: 600)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
