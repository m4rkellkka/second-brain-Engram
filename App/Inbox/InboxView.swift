import EngramKit
import SwiftUI

struct InboxView: View {
  @Environment(AppModel.self) private var model
  @State private var kind: EntryKind?
  @State private var items: [InboxItem] = []
  @State private var projects: [Project] = []
  @State private var loadError: String?

  var body: some View {
    VStack(spacing: 0) {
      // Header and capture stay put; only the feed scrolls, so focusing the
      // capture field never scrolls the page.
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Inbox").font(.geist(24, .semibold)).foregroundStyle(Theme.text)
          Text("Typed thoughts wait here until Claude sorts them.")
            .font(.geist(13))
            .foregroundStyle(Theme.textMuted)
        }
        CaptureBox()
        KindFilter(selection: $kind)
      }
      .padding(.horizontal, 32)
      .padding(.top, 28)
      .padding(.bottom, 16)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)

      ScrollView {
        Group {
          if let loadError {
            Text(loadError).font(.geist(13)).foregroundStyle(Theme.danger)
          } else if items.isEmpty {
            Text(kind == nil ? "Nothing here yet. Write your first thought above." : "No entries.")
              .font(.geist(13.5))
              .foregroundStyle(Theme.textSubtle)
              .padding(.top, 24)
              .frame(maxWidth: .infinity)
          } else {
            LazyVStack(spacing: 10) {
              ForEach(items) { item in
                EntryRow(item: item, projects: projects)
              }
            }
          }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
      }
      .scrollContentBackground(.hidden)
    }
    .task(id: kind) { await observeInbox() }
    .task { await observeProjects() }
  }

  private func observeInbox() async {
    guard let database = model.database else { return }
    do {
      for try await rows in database.inboxUpdates(kind: kind) {
        items = rows
        loadError = nil
      }
    } catch {
      loadError = "Couldn't load the Inbox: \(error.localizedDescription)"
    }
  }

  private func observeProjects() async {
    guard let database = model.database else { return }
    do {
      for try await rows in database.activeProjectUpdates() { projects = rows }
    } catch {
      loadError = "Couldn't load projects: \(error.localizedDescription)"
    }
  }
}

private struct KindFilter: View {
  @Binding var selection: EntryKind?

  private let options: [(title: String, kind: EntryKind?)] = [
    ("All", nil), ("Ideas", .idea), ("Tasks", .task), ("Notes", .note), ("Links", .link),
  ]

  var body: some View {
    HStack(spacing: 6) {
      ForEach(options, id: \.title) { option in
        let isSelected = option.kind == selection
        Button {
          selection = option.kind
        } label: {
          Text(option.title)
            .font(.geist(12.5, isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(isSelected ? Theme.surface2 : .clear))
            .overlay(Capsule().stroke(isSelected ? Theme.borderStrong : Theme.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }
}

#Preview("Inbox") {
  InboxView()
    .environment(AppModel.preview())
    .frame(width: 800, height: 700)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("Inbox, empty") {
  InboxView()
    .environment(AppModel.preview(withSamples: false))
    .frame(width: 800, height: 500)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
