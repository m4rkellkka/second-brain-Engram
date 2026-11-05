import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      Sidebar(selection: $model.section)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    } detail: {
      Group {
        if let error = model.loadError {
          EmptyState(symbol: "exclamationmark.triangle", title: "Engram can't start", text: error)
        } else {
          switch model.section {
          case .inbox: InboxView()
          case .projects: ProjectsView()
          case .brain: BrainView()
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.background)
    }
    .toolbar(removing: .title)
    .toolbarBackground(Theme.background, for: .windowToolbar)
    .containerBackground(Theme.background, for: .window)
  }
}

private struct Sidebar: View {
  @Binding var selection: Section

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "point.3.connected.trianglepath.dotted")
          .foregroundStyle(Theme.accent)
        Text("Engram").font(.geist(15, .semibold)).foregroundStyle(Theme.text)
      }
      .padding(.horizontal, 16)
      .padding(.top, 6)
      .padding(.bottom, 14)

      VStack(spacing: 2) {
        ForEach(Section.allCases) { section in
          SidebarRow(section: section, isSelected: section == selection) {
            selection = section
          }
        }
      }
      .padding(.horizontal, 8)

      Spacer()

      Text("v\(Bundle.main.appVersion)")
        .font(.geistMono(11))
        .foregroundStyle(Theme.textSubtle)
        .padding(16)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.sidebar)
  }
}

private struct SidebarRow: View {
  let section: Section
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: section.symbol)
          .frame(width: 18)
          .foregroundStyle(isSelected ? Theme.accent : Theme.textMuted)
        Text(section.title)
          .font(.geist(13.5, isSelected ? .medium : .regular))
          .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
        Spacer()
      }
      .padding(.horizontal, 10)
      .frame(height: 32)
      .background(
        RoundedRectangle(cornerRadius: Theme.controlRadius)
          .fill(isSelected ? Theme.surface2 : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

extension Bundle {
  var appVersion: String {
    object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }
}

#Preview("Window") {
  RootView()
    .environment(AppModel.preview())
    .frame(width: 1000, height: 680)
    .preferredColorScheme(.dark)
}
