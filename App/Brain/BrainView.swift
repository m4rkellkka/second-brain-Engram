import SwiftUI

struct BrainView: View {
  var body: some View {
    EmptyState(
      symbol: "point.3.connected.trianglepath.dotted",
      title: "Brain",
      text: "The 3D graph of your notes arrives in a later version.")
  }
}

#Preview("Brain") {
  BrainView()
    .frame(width: 700, height: 500)
    .background(Theme.background)
    .preferredColorScheme(.dark)
    .onAppear { Fonts.register() }
}
