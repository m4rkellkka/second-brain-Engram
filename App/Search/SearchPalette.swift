import EngramKit
import SwiftUI

/// ⌘K: search every entry (and project names) as you type.
struct SearchPalette: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [InboxItem] = []
  @State private var projects: [Project] = []
  @State private var expanded: Set<String> = []
  @FocusState private var focused: Bool

  private var terms: [String] {
    query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count > 1 }
  }

  private var matchingProjects: [Project] {
    guard !terms.isEmpty else { return [] }
    return projects.filter { project in
      terms.contains { project.name.localizedCaseInsensitiveContains($0) }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Theme.accent)
        TextField("Search your notes", text: $query)
          .textFieldStyle(.plain)
          .font(.geist(17))
          .focused($focused)
        Button("esc") { dismiss() }
          .keyboardShortcut(.cancelAction)
          .buttonStyle(.plain)
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
          .help("Close")
      }
      .padding(.horizontal, 18)
      .frame(height: 56)

      Rectangle().fill(Theme.border).frame(height: 1)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          if !matchingProjects.isEmpty {
            SectionLabel("Projects").padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            ForEach(matchingProjects) { project in
              Button {
                model.openProject(project.id)
                dismiss()
              } label: {
                HStack(spacing: 10) {
                  Circle().fill(Color(hexString: project.color)).frame(width: 8, height: 8)
                  Text(highlighted(project.name)).font(.geist(14)).foregroundStyle(Theme.text)
                  Spacer()
                  Text("open").font(.geistMono(11)).foregroundStyle(Theme.accent)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .focusEffectDisabled()
            }
          }
          if results.isEmpty, matchingProjects.isEmpty {
            Text(query.isEmpty ? "Type to search entries and keywords." : "Nothing found.")
              .font(.geist(13))
              .foregroundStyle(Theme.textSubtle)
              .padding(18)
          }
          if !results.isEmpty {
            SectionLabel("Entries · \(results.count)")
              .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
          }
          ForEach(results) { item in
            ResultRow(
              item: item, text: highlighted(item.entry.content),
              isExpanded: expanded.contains(item.id)
            ) {
              if expanded.remove(item.id) == nil { expanded.insert(item.id) }
            }
          }
        }
        .padding(8)
      }
      .frame(height: 380)

      Rectangle().fill(Theme.border).frame(height: 1)
      HStack(spacing: 16) {
        Text("click to expand · ↗ opens the project")
        Spacer()
        Text(
          "\(results.count) entr\(results.count == 1 ? "y" : "ies") · \(matchingProjects.count) project\(matchingProjects.count == 1 ? "" : "s")"
        )
      }
      .font(.geistMono(11))
      .foregroundStyle(Theme.textSubtle)
      .padding(.horizontal, 18)
      .frame(height: 36)
    }
    .frame(width: 640)
    .background(Theme.glass)
    .background(.ultraThinMaterial)
    .onAppear { focused = true }
    .task(id: model.externalChanges) {
      guard let database = model.database else { return }
      projects = (try? await database.writer.read(AppDatabase.fetchActiveProjects)) ?? []
    }
    .task(id: query) {
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      let text = query
      guard let database = model.database else { return }
      results = (try? await database.writer.read { try AppDatabase.search($0, query: text) }) ?? []
    }
  }

  /// The text with every search term washed in the accent.
  private func highlighted(_ text: String) -> AttributedString {
    var result = AttributedString(text)
    for term in terms {
      var searchStart = result.startIndex
      while searchStart < result.endIndex,
        let range = result[searchStart...].range(
          of: term, options: [.caseInsensitive, .diacriticInsensitive])
      {
        result[range].backgroundColor = Theme.accent.opacity(0.25)
        searchStart = range.upperBound
      }
    }
    return result
  }
}

private struct ResultRow: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let item: InboxItem
  let text: AttributedString
  let isExpanded: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      VStack(alignment: .leading, spacing: 4) {
        Text(text)
          .font(.geist(14))
          .foregroundStyle(Theme.text)
          .lineLimit(isExpanded ? nil : 2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 0) {
          Text(item.entry.kind.rawValue).foregroundStyle(Theme.kindColor(item.entry.kind.rawValue))
          if let project = item.project { Text(" · \(project.name)") }
          Text(" · ")
          Text(item.entry.createdAt, format: .dateTime.day().month(.abbreviated))
          Spacer()
          if let project = item.project {
            Button {
              model.openProject(project.id)
              dismiss()
            } label: {
              Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(project.name)")
            .accessibilityLabel("Open project \(project.name)")
          }
        }
        .font(.geist(12))
        .foregroundStyle(Theme.textSubtle)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 12).fill(isExpanded ? Theme.surface2 : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
  }
}
