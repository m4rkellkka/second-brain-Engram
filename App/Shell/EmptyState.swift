import SwiftUI

struct EmptyState: View {
  let symbol: String
  let title: String
  let text: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 30, weight: .light))
        .foregroundStyle(Theme.textSubtle)
      Text(title).font(.geist(17, .semibold)).foregroundStyle(Theme.text)
      Text(text)
        .font(.geist(13.5))
        .foregroundStyle(Theme.textMuted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
