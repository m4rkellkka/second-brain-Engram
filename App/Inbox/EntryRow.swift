import EngramKit
import SwiftUI

struct EntryRow: View {
  let item: InboxItem
  let projects: [Project]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        KindBadge(kind: item.entry.kind)
        Spacer()
        Text(item.entry.createdAt, format: .relative(presentation: .named))
          .font(.geistMono(11))
          .foregroundStyle(Theme.textSubtle)
      }
      Text(item.entry.content)
        .font(.geist(14.5))
        .foregroundStyle(Theme.text)
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
      ProjectPicker(entryID: item.entry.id, current: item.project, projects: projects)
    }
    .padding(16)
    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
  }
}

private struct KindBadge: View {
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
