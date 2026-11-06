import EngramKit
import SwiftUI

struct ProjectPageView: View {
  @Environment(AppModel.self) private var model
  let projectID: String
  @State private var page: ProjectPage?
  @State private var error: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Button {
          model.openProjectID = nil
        } label: {
          Label("Projects", systemImage: "chevron.left")
            .font(.geist(12.5))
            .foregroundStyle(Theme.textMuted)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()

        if let page {
          ProjectHeader(project: page.project) { error = $0 }
          if let error {
            Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
          }
          LiveContextCard(project: page.project)
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
            alignment: .leading, spacing: 16
          ) {
            TasksCard(open: page.openTasks, done: page.doneTasks)
            ForEach([ContextSection.decision, .idea, .stack], id: \.self) { section in
              ContextSectionCard(
                section: section, lines: page.sections[section] ?? [], projectID: page.project.id)
            }
          }
          RecentCard(entries: page.recentEntries)
        } else {
          Text("This project no longer exists.").font(.geist(13)).foregroundStyle(Theme.textSubtle)
        }
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 22)
      .frame(maxWidth: 1040)
      .frame(maxWidth: .infinity)
    }
    .scrollContentBackground(.hidden)
    .task(id: PageKey(id: projectID, changes: model.externalChanges)) {
      guard let database = model.database else { return }
      do {
        for try await value in database.projectPageUpdates(projectID) { page = value }
      } catch {
        self.error = "Couldn't load the project: \(error.localizedDescription)"
      }
    }
  }
}

private struct PageKey: Hashable {
  var id: String
  var changes: Int
}

// MARK: - Header

private struct ProjectHeader: View {
  @Environment(AppModel.self) private var model
  let project: Project
  let report: (String?) -> Void
  @State private var isRenaming = false
  @State private var isRecoloring = false

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          Circle().fill(Color(hexString: project.color)).frame(width: 14, height: 14)
          Text(project.name).font(.geist(28, .semibold)).tracking(-0.4)
            .foregroundStyle(Theme.text)
          if project.archivedAt != nil {
            Text("archived").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
              .padding(.horizontal, 9).frame(height: 22)
              .overlay(Capsule().strokeBorder(Theme.borderStrong))
          }
        }
        HStack(spacing: 8) {
          if let status = project.status {
            Text(status)
              .font(.geistMono(11))
              .foregroundStyle(Theme.text)
              .padding(.horizontal, 10)
              .frame(height: 24)
              .overlay(Capsule().strokeBorder(Theme.borderStrong))
          }
          if let updated = project.contextUpdatedAt {
            Text(
              "\(project.statusSource == .user ? "status by you" : "status by Claude") · updated \(updated.formatted(.relative(presentation: .named)))"
            )
            .font(.geist(12))
            .foregroundStyle(Theme.textSubtle)
          }
        }
      }
      Spacer()
      Button("Show in Brain") { model.showInBrain(project.id) }
        .buttonStyle(QuietButtonStyle())
      Menu {
        Button("Rename…") { isRenaming = true }
        Button("Change color…") { isRecoloring = true }
        Divider()
        if project.archivedAt == nil {
          Button("Archive") {
            report(model.change { try $0.setArchived(true, projectID: project.id) })
          }
        } else {
          Button("Unarchive") {
            report(model.change { try $0.setArchived(false, projectID: project.id) })
          }
        }
      } label: {
        Image(systemName: "ellipsis")
          .foregroundStyle(Theme.text)
          .frame(width: 32, height: 32)
          .glassPanel(radius: Theme.controlRadius)
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel("Project actions")
      .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
        TextPrompt(title: "Rename project", initial: project.name, action: "Rename") { name in
          let message = model.change { try $0.renameProject(project.id, to: name) }
          if message == nil { isRenaming = false }
          return message
        }
      }
      .popover(isPresented: $isRecoloring, arrowEdge: .bottom) {
        HStack(spacing: 10) {
          ForEach(ProjectNaming.colors, id: \.self) { color in
            Button {
              report(model.change { try $0.recolorProject(project.id, to: color) })
              isRecoloring = false
            } label: {
              Circle().fill(Color(hexString: color)).frame(width: 24, height: 24)
                .overlay(Circle().stroke(Theme.text, lineWidth: color == project.color ? 2 : 0))
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Color \(color)")
          }
        }
        .padding(12)
      }
    }
  }
}

// MARK: - Summary and status

private struct LiveContextCard: View {
  @Environment(AppModel.self) private var model
  let project: Project

  var body: some View {
    Card(glass: true) {
      VStack(alignment: .leading, spacing: 14) {
        SectionLabel("Live context")
        EditableText(
          text: project.summary, placeholder: "No summary yet. Claude writes one as you talk.",
          source: project.summarySource, font: .geist(15), multiline: true,
          save: { text in
            model.change { try $0.setProjectText(.summary, to: text, projectID: project.id) }
          },
          handBack: { model.change { try $0.handBackToClaude(.summary, projectID: project.id) } })
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text("Status").font(.geist(12.5)).foregroundStyle(Theme.textSubtle).frame(
            width: 52, alignment: .leading)
          EditableText(
            text: project.status, placeholder: "—", source: project.statusSource,
            font: .geist(13.5, .medium), multiline: false,
            save: { text in
              model.change { try $0.setProjectText(.status, to: text, projectID: project.id) }
            },
            handBack: { model.change { try $0.handBackToClaude(.status, projectID: project.id) } })
        }
      }
    }
  }
}

/// Text that switches to an editor on "Edit", with who wrote it.
private struct EditableText: View {
  let text: String?
  let placeholder: String
  let source: ContextSource
  let font: Font
  let multiline: Bool
  let save: (String) -> String?
  let handBack: () -> String?

  @State private var draft = ""
  @State private var isEditing = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if isEditing {
        TextField("", text: $draft, axis: multiline ? .vertical : .horizontal)
          .textFieldStyle(.plain)
          .font(font)
          .lineLimit(multiline ? 2...8 : 1...1)
          .padding(10)
          .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface2))
          .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.borderStrong))
          .onSubmit { if !multiline { commit() } }
        HStack(spacing: 8) {
          SmallButton(title: "Save", symbol: "checkmark", action: commit)
          SmallButton(title: "Cancel", symbol: "xmark") { isEditing = false }
        }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(text ?? placeholder)
            .font(font)
            .foregroundStyle(text == nil ? Theme.textSubtle : Theme.text)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button("Edit") {
            draft = text ?? ""
            error = nil
            isEditing = true
          }
          .buttonStyle(.plain)
          .font(.geist(12))
          .foregroundStyle(Theme.textMuted)
        }
        if text != nil || source == .user {
          HStack(spacing: 8) {
            Text(source == .user ? "edited by you" : "by Claude")
              .font(.geistMono(10.5)).foregroundStyle(Theme.textSubtle)
            if source == .user {
              Button("Let Claude update") { error = handBack() }
                .buttonStyle(.plain)
                .font(.geist(11.5))
                .foregroundStyle(Theme.accent)
            }
          }
        }
      }
      if let error { Text(error).font(.geist(12)).foregroundStyle(Theme.danger) }
    }
  }

  private func commit() {
    error = save(draft)
    if error == nil { isEditing = false }
  }
}

// MARK: - Stack, decisions, ideas

private struct ContextSectionCard: View {
  @Environment(AppModel.self) private var model
  let section: ContextSection
  let lines: [ContextLine]
  let projectID: String
  @State private var newText = ""
  @State private var error: String?

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 10) {
        SectionLabel(lines.isEmpty ? section.title : "\(section.title) · \(lines.count)")
        if lines.isEmpty {
          Text("Nothing yet.").font(.geist(12.5)).foregroundStyle(Theme.textSubtle)
        }
        ForEach(lines) { line in ContextLineRow(line: line) }
        HStack(spacing: 8) {
          TextField(
            "Add \(section == .stack ? "to the stack" : section == .decision ? "a decision" : "an idea")",
            text: $newText
          )
          .textFieldStyle(.plain)
          .font(.geist(13))
          .padding(.horizontal, 10)
          .frame(height: 30)
          .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface2))
          .onSubmit(add)
          if !newText.trimmingCharacters(in: .whitespaces).isEmpty {
            SmallButton(title: "Add", symbol: "plus", action: add)
          }
        }
        if let error { Text(error).font(.geist(12)).foregroundStyle(Theme.danger) }
      }
    }
  }

  private func add() {
    let text = newText
    error = model.change { try $0.addContextItem(section, text: text, projectID: projectID) }
    if error == nil { newText = "" }
  }
}

private struct ContextLineRow: View {
  @Environment(AppModel.self) private var model
  let line: ContextLine
  @State private var showSources = false
  @State private var isEditing = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Circle().fill(Theme.textSubtle).frame(width: 4, height: 4).offset(y: -3)
        Text(line.item.text)
          .font(.geist(13.5))
          .foregroundStyle(Theme.text)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        if !line.sources.isEmpty {
          Button("from \(line.sources.count) note\(line.sources.count == 1 ? "" : "s")") {
            showSources.toggle()
          }
          .buttonStyle(.plain)
          .font(.geistMono(10.5))
          .foregroundStyle(Theme.accent)
        } else if line.item.source == .user {
          Text("you").font(.geistMono(10.5)).foregroundStyle(Theme.textSubtle)
        }
        Menu {
          Button("Edit…") { isEditing = true }
          Button("Remove") { error = model.change { try $0.dismissContextItem(line.item.id) } }
        } label: {
          Image(systemName: "ellipsis").foregroundStyle(Theme.textSubtle).frame(
            width: 24, height: 24)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Item actions")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
          TextPrompt(title: "Edit item", initial: line.item.text, action: "Save") { text in
            let message = model.change { try $0.editContextItem(line.item.id, text: text) }
            if message == nil { isEditing = false }
            return message
          }
        }
      }
      if showSources {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(line.sources) { entry in
            Text(entry.content)
              .font(.geist(12.5))
              .foregroundStyle(Theme.textMuted)
              .padding(.leading, 12)
              .overlay(alignment: .leading) {
                Rectangle().fill(Theme.borderStrong).frame(width: 2)
              }
          }
        }
        .padding(.leading, 12)
      }
      if let error { Text(error).font(.geist(12)).foregroundStyle(Theme.danger) }
    }
  }
}

// MARK: - Tasks and recent entries

private struct TasksCard: View {
  let open: [InboxItem]
  let done: [InboxItem]
  @State private var showDone = false

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 10) {
        SectionLabel(open.isEmpty ? "Open tasks" : "Open tasks · \(open.count)")
        if open.isEmpty {
          Text("No open tasks.").font(.geist(12.5)).foregroundStyle(Theme.textSubtle)
        }
        ForEach(open) { item in TaskRow(item: item) }
        if !done.isEmpty {
          DisclosureGroup(isExpanded: $showDone) {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(done) { item in TaskRow(item: item) }
            }
            .padding(.top, 6)
          } label: {
            Text("Done (\(done.count))").font(.geist(12.5)).foregroundStyle(Theme.textMuted)
          }
        }
      }
    }
  }
}

struct TaskRow: View {
  @Environment(AppModel.self) private var model
  let item: InboxItem

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      TaskCheckbox(item: item)
      Text(item.entry.content)
        .font(.geist(13.5))
        .foregroundStyle(item.entry.doneAt == nil ? Theme.text : Theme.textSubtle)
        .strikethrough(item.entry.doneAt != nil, color: Theme.textSubtle)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let due = item.entry.dueAt {
        Text(due.formatted(date: .abbreviated, time: .omitted))
          .font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
      }
    }
  }
}

/// A round checkbox that ticks a task.
struct TaskCheckbox: View {
  @Environment(AppModel.self) private var model
  let item: InboxItem

  var body: some View {
    let done = item.entry.doneAt != nil
    Button {
      _ = model.setDone(!done, entryID: item.entry.id)
    } label: {
      Image(systemName: done ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 16))
        .foregroundStyle(done ? Theme.kindColor("note") : Theme.textSubtle)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(done ? "Mark as not done" : "Mark as done")
  }
}

private struct RecentCard: View {
  let entries: [InboxItem]

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 10) {
        SectionLabel("Recent")
        if entries.isEmpty {
          Text("Nothing yet.").font(.geist(12.5)).foregroundStyle(Theme.textSubtle)
        }
        ForEach(entries) { item in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            KindBadge(kind: item.entry.kind)
            Text(item.entry.content)
              .font(.geist(13.5))
              .foregroundStyle(Theme.text)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.entry.createdAt, format: .dateTime.day().month(.abbreviated))
              .font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
          }
        }
      }
    }
  }
}

// MARK: - Shared bits

/// A section of the page: quiet by default, glass for the live context.
private struct Card<Content: View>: View {
  var glass = false
  @ViewBuilder let content: Content

  var body: some View {
    let padded = content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
    if glass {
      padded.glassPanel()
    } else {
      padded.quietCard()
    }
  }
}

/// A small one-field form in a popover.
struct TextPrompt: View {
  let title: String
  let initial: String
  let action: String
  /// Returns an error message, or `nil` when done.
  let submit: (String) -> String?

  @State private var text = ""
  @State private var error: String?
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.geist(13, .semibold)).foregroundStyle(Theme.text)
      TextField("", text: $text)
        .textFieldStyle(.plain)
        .font(.geist(14))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.borderStrong))
        .focused($focused)
        .onSubmit { error = submit(text) }
      if let error { Text(error).font(.geist(12)).foregroundStyle(Theme.danger) }
      HStack {
        Spacer()
        Button(action) { error = submit(text) }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(14)
    .frame(width: 300)
    .onAppear {
      text = initial
      focused = true
    }
  }
}

#Preview("Project page") {
  let model = AppModel.preview()
  let id =
    (try? model.database?.writer.read { try AppDatabase.fetchActiveProjects($0) }.first?.id) ?? ""
  return ProjectPageView(projectID: id)
    .environment(model)
    .frame(width: 800, height: 900)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
