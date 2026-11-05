import SwiftUI

struct ProjectsView: View {
  var body: some View {
    EmptyState(
      symbol: "folder",
      title: "Projects",
      text:
        "Project pages with a live context arrive in a later version. Projects you create "
        + "from the Inbox are already saved and will show up here.")
  }
}

#Preview("Projects") {
  ProjectsView()
    .frame(width: 700, height: 500)
    .background(Theme.background)
    .preferredColorScheme(.dark)
    .onAppear { Fonts.register() }
}
