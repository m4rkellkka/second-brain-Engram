import EngramKit
import SwiftUI

/// Files an entry into a project, or creates a new one inline.
struct ProjectPicker: View {
  @Environment(AppModel.self) private var model
  let entryID: String
  let current: Project?
  let projects: [Project]

  @State private var isCreating = false
  @State private var error: String?

  var body: some View {
    HStack(spacing: 8) {
      Menu {
        Button {
          assign(nil)
        } label: {
          if current == nil {
            Label("No project", systemImage: "checkmark")
          } else {
            Text("No project")
          }
        }
        if !projects.isEmpty { Divider() }
        ForEach(projects) { project in
          Button {
            assign(project.id)
          } label: {
            if project.id == current?.id {
              Label(project.name, systemImage: "checkmark")
            } else {
              Text(project.name)
            }
          }
        }
        Divider()
        Button("New project…") { isCreating = true }
      } label: {
        HStack(spacing: 6) {
          Circle()
            .fill(current.map { Color(hexString: $0.color) } ?? Theme.textSubtle.opacity(0.5))
            .frame(width: 7, height: 7)
          Text(current?.name ?? "No project")
            .font(.geist(12.5))
            .foregroundStyle(current == nil ? Theme.textSubtle : Theme.textMuted)
          Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.textSubtle)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .overlay(Capsule().strokeBorder(Theme.borderStrong.opacity(0.7)))
        .contentShape(Capsule())
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel("Project")
      .popover(isPresented: $isCreating, arrowEdge: .bottom) {
        NewProjectForm { name in
          let message = model.fileEntry(entryID, intoNewProjectNamed: name)
          if message == nil { isCreating = false }
          return message
        }
      }

      if let error {
        Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
      }
    }
  }

  private func assign(_ projectID: String?) {
    error = model.setProject(projectID, forEntry: entryID)
  }
}

struct NewProjectForm: View {
  /// Returns an error message, or `nil` when the project was created.
  let create: (String) -> String?

  @State private var name = ""
  @State private var error: String?
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("New project").font(.geist(13, .semibold)).foregroundStyle(Theme.text)
      TextField("Name", text: $name)
        .textFieldStyle(.plain)
        .font(.geist(14))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong)
        )
        .focused($focused)
        .onSubmit(submit)
      if let error {
        Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
      }
      HStack {
        Spacer()
        Button("Create", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(14)
    .frame(width: 260)
    .onAppear { focused = true }
  }

  private func submit() {
    error = create(name)
  }
}
