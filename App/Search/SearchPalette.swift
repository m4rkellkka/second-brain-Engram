import EngramKit
import SwiftUI

/// ⌘K: search every entry as you type.
struct SearchPalette: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [InboxItem] = []
  @State private var expanded: Set<String> = []
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSubtle)
        TextField("Search your notes", text: $query)
          .textFieldStyle(.plain)
          .font(.geist(16))
          .focused($focused)
        Button("Close") { dismiss() }
          .keyboardShortcut(.cancelAction)
          .buttonStyle(.plain)
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
      }
      .padding(.horizontal, 18)
      .frame(height: 54)

      Rectangle().fill(Theme.border).frame(height: 1)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          if results.isEmpty {
            Text(query.isEmpty ? "Type to search entries and keywords." : "Nothing found.")
              .font(.geist(13))
              .foregroundStyle(Theme.textSubtle)
              .padding(18)
          }
          ForEach(results) { item in
            ResultRow(item: item, isExpanded: expanded.contains(item.id)) {
              if expanded.remove(item.id) == nil { expanded.insert(item.id) }
            }
          }
        }
        .padding(8)
      }
      .frame(height: 380)
    }
    .frame(width: 620)
    .background(Theme.background)
    .onAppear { focused = true }
    .task(id: query) {
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      let text = query
      guard let database = model.database else { return }
      results = (try? await database.writer.read { try AppDatabase.search($0, query: text) }) ?? []
    }
  }
}

private struct ResultRow: View {
  let item: InboxItem
  let isExpanded: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          KindBadge(kind: item.entry.kind)
          if let project = item.project {
            HStack(spacing: 5) {
              Circle().fill(Color(hexString: project.color)).frame(width: 6, height: 6)
              Text(project.name).font(.geist(12)).foregroundStyle(Theme.textMuted)
            }
          }
          Spacer()
          Text(item.entry.createdAt, format: .dateTime.day().month(.abbreviated))
            .font(.geistMono(11))
            .foregroundStyle(Theme.textSubtle)
        }
        Text(item.entry.content)
          .font(.geist(14))
          .foregroundStyle(Theme.text)
          .lineLimit(isExpanded ? nil : 2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
