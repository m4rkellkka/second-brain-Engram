import EngramKit
import SwiftUI

/// The main window: a top bar with the tabs, and the open tab below it.
struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      TopBar()
      Group {
        if let error = model.loadError {
          EmptyState(symbol: "exclamationmark.triangle", title: "Engram can't start", text: error)
        } else {
          switch model.section {
          case .today: TodayView()
          case .journal: JournalView()
          case .inbox: InboxView()
          case .projects: ProjectsView()
          case .brain: BrainView()
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Theme.background)
    .ignoresSafeArea(.container, edges: .top)
    .sheet(isPresented: $model.isSearching) { SearchPalette() }
    .containerBackground(Theme.background, for: .window)
    #if DEBUG
      // `-EngramWindowSize 1280x800`: a fixed window size for screenshots.
      .onAppear {
        guard let raw = UserDefaults.standard.string(forKey: "EngramWindowSize") else { return }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        DispatchQueue.main.async {
          NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(AppModel.mainWindowID) == true }?
          .setContentSize(NSSize(width: parts[0], height: parts[1]))
        }
      }
    #endif
  }
}

/// Tabs in the middle, search and settings on the right. The window's own
/// title bar is hidden, so the empty parts of this bar drag the window.
private struct TopBar: View {
  @Environment(AppModel.self) private var model
  @State private var waiting = 0

  static let height: CGFloat = 52

  var body: some View {
    @Bindable var model = model
    ZStack {
      Color.clear
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())

      SectionTabs(selection: $model.section, inboxBadge: waiting) { section in
        // Clicking Projects again goes back to the list, Journal to today.
        if section == .projects { model.openProjectID = nil }
        if section == .journal { model.openJournalDay = nil }
      }

      HStack(spacing: 8) {
        Spacer()
        Button {
          model.isSearching = true
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
            Text("Search").font(.geist(13))
            Text("⌘K").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
          }
          .foregroundStyle(Theme.textMuted)
          .padding(.horizontal, 12)
          .frame(height: 30)
          .glassPanel(radius: 9)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Search your notes (⌘K)")

        SettingsLink {
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textMuted)
            .frame(width: 30, height: 30)
            .glassPanel(radius: 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
      }
      .padding(.trailing, 16)
    }
    // Room on the left for the window's traffic lights.
    .padding(.leading, 78)
    .frame(height: Self.height)
    .background(Theme.background.opacity(0.92))
    .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    .task(id: model.externalChanges) {
      guard let database = model.database else { return }
      do {
        for try await value in database.waitingCountUpdates() { waiting = value }
      } catch {}
    }
  }
}

/// The segmented tabs in the top bar.
private struct SectionTabs: View {
  @Binding var selection: Section
  let inboxBadge: Int
  let onSelect: (Section) -> Void

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Section.allCases) { section in
        let isSelected = section == selection
        Button {
          selection = section
          onSelect(section)
        } label: {
          HStack(spacing: 6) {
            Text(section.title)
              .font(.geist(13, isSelected ? .medium : .regular))
              .foregroundStyle(isSelected ? Theme.accent : Theme.textMuted)
            if section == .inbox, inboxBadge > 0 {
              Text("\(inboxBadge)")
                .font(.geistMono(11))
                .foregroundStyle(isSelected ? Theme.text : Theme.accent)
            }
          }
          .padding(.horizontal, 14)
          .frame(height: 28)
          .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(isSelected ? Theme.accentWash : .clear)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help("\(section.title) (⌘\((Section.allCases.firstIndex(of: section) ?? 0) + 1))")
      }
    }
    .padding(3)
    .glassPanel(radius: 12)
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
    .frame(width: 1040, height: 720)
    .preferredColorScheme(.dark)
}
