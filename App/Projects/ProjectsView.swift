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
  private let columns = [GridItem(.adaptive(minimum: 250), spacing: 16)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .bottom) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Projects").font(.geist(26, .semibold)).tracking(-0.4)
              .foregroundStyle(Theme.text)
            Text("Each page keeps itself up to date from what you save with Claude.")
              .font(.geist(13))
              .foregroundStyle(Theme.textSubtle)
          }
          Spacer()
          Button {
            isCreating = true
          } label: {
            Label("New project", systemImage: "plus")
          }
          .buttonStyle(AccentButtonStyle())
          .popover(isPresented: $isCreating, arrowEdge: .bottom) { newProjectForm }
        }

        if active.isEmpty {
          Text("No projects yet. Create one, or confirm one Claude suggests in the Inbox.")
            .font(.geist(13.5))
            .foregroundStyle(Theme.textSubtle)
            .padding(.top, 12)
        }
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
          ForEach(active) { row in ProjectCard(row: row) }
          if !active.isEmpty {
            Button {
              isCreating = true
            } label: {
              VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                Text("New project").font(.geist(13))
              }
              .foregroundStyle(Theme.textMuted)
              .frame(maxWidth: .infinity, minHeight: 150)
              .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                  .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
              )
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
          }
        }

        if !archived.isEmpty {
          Button {
            withAnimation(.easeOut(duration: 0.2)) { showArchived.toggle() }
          } label: {
            Label(
              "Archived (\(archived.count))",
              systemImage: showArchived ? "chevron.down" : "chevron.right"
            )
            .font(.geist(13, .medium))
            .foregroundStyle(Theme.textSubtle)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .focusEffectDisabled()
          if showArchived {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
              ForEach(archived) { row in ProjectCard(row: row).opacity(0.7) }
            }
          }
        }
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 28)
      .frame(maxWidth: 1120)
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

  private var newProjectForm: some View {
    NewProjectForm { name in
      let message = model.createProject(named: name)
      if message == nil { isCreating = false }
      return message
    }
  }
}

/// A project on the list: name, status, the start of its summary and counts.
private struct ProjectCard: View {
  @Environment(AppModel.self) private var model
  let row: ProjectOverview

  var body: some View {
    let color = Color(hexString: row.project.color)
    Button {
      model.openProject(row.project.id)
    } label: {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Circle().fill(color).frame(width: 10, height: 10)
          Text(row.project.name).font(.geist(16, .semibold)).foregroundStyle(Theme.text)
            .lineLimit(1)
          Spacer(minLength: 0)
          if row.addedToday > 0 {
            Text("+\(row.addedToday) today").font(.geistMono(11)).foregroundStyle(Theme.accent)
          }
          if row.project.archivedAt != nil {
            Text("archived").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
          }
        }
        if let status = row.project.status {
          Text(status)
            .font(.geistMono(11))
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
        }
        Text(row.project.summary ?? "No summary yet. Claude writes one as you talk.")
          .font(.geist(13))
          .foregroundStyle(row.project.summary == nil ? Theme.textSubtle : Theme.textMuted)
          .lineSpacing(2)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 0)
        HStack {
          Text("\(row.openTasks) open · \(row.entryCount) entr\(row.entryCount == 1 ? "y" : "ies")")
          Spacer()
          if let activity = row.lastActivity {
            Text(activity, format: .relative(presentation: .named))
          }
        }
        .font(.geistMono(11))
        .foregroundStyle(Theme.textSubtle)
      }
      .padding(18)
      .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
      .glassPanel(
        border: row.addedToday > 0 ? color.opacity(0.35) : Theme.borderStrong.opacity(0.7)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
  }
}

#Preview("Projects") {
  ProjectsView()
    .environment(AppModel.preview())
    .frame(width: 800, height: 600)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
