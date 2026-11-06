import EngramKit
import SwiftUI

/// "Filter" with a count of what is hidden; the popover picks projects,
/// kinds, journal days and a period. Filters only hide, nothing moves.
struct FilterButton: View {
  @Binding var filter: GraphFilter
  let projects: [Project]
  @State private var open = false

  var body: some View {
    Button {
      open.toggle()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11, weight: .medium))
        Text("Filter").font(.geist(12.5))
        if filter.isActive {
          Text("\(filter.activeCount)").font(.geistMono(11)).foregroundStyle(Theme.accent)
        }
      }
      .foregroundStyle(filter.isActive ? Theme.text : Theme.textMuted)
      .padding(.horizontal, 10)
      .frame(height: 30)
      .glassPanel(
        radius: 9,
        border: filter.isActive ? Theme.accent.opacity(0.45) : Theme.borderStrong.opacity(0.7)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .help("Filter the graph")
    .popover(isPresented: $open, arrowEdge: .bottom) {
      FilterPanel(filter: $filter, projects: projects)
    }
  }
}

private struct FilterPanel: View {
  @Binding var filter: GraphFilter
  let projects: [Project]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        SectionLabel("Show")
        Spacer()
        if filter.isActive {
          Button("Show all") { filter = GraphFilter() }
            .buttonStyle(.plain)
            .font(.geist(12))
            .foregroundStyle(Theme.accent)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        ForEach(projects) { project in
          toggle(
            project.name, color: Color(hexString: project.color),
            isOn: !filter.hiddenProjects.contains(project.id)
          ) { on in
            if on {
              filter.hiddenProjects.remove(project.id)
            } else {
              filter.hiddenProjects.insert(project.id)
            }
          }
        }
        toggle("Inbox (not filed)", color: Theme.textSubtle, isOn: filter.showUnfiled) {
          filter.showUnfiled = $0
        }
        toggle("Journal days", color: Theme.text, isOn: filter.showJournal) {
          filter.showJournal = $0
        }
      }

      Divider().overlay(Theme.border)

      HStack(spacing: 6) {
        ForEach(EntryKind.allCases, id: \.self) { kind in
          FilterChip(title: kind.rawValue, isSelected: filter.kinds.contains(kind)) {
            if filter.kinds.contains(kind) {
              filter.kinds.remove(kind)
            } else {
              filter.kinds.insert(kind)
            }
          }
        }
      }

      Picker("Period", selection: $filter.period) {
        ForEach(GraphFilter.Period.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    .padding(16)
    .frame(width: 360)
  }

  private func toggle(
    _ title: String, color: Color, isOn: Bool, set: @escaping (Bool) -> Void
  ) -> some View {
    Button {
      set(!isOn)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isOn ? "checkmark.square.fill" : "square")
          .foregroundStyle(isOn ? Theme.accent : Theme.textSubtle)
        Circle().fill(color).frame(width: 7, height: 7)
        Text(title).font(.geist(13)).foregroundStyle(isOn ? Theme.text : Theme.textMuted)
        Spacer()
      }
      .frame(height: 28)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
  }
}

/// ⌘F: searches the graph through full-text search; matches stay lit.
struct GraphSearchField: View {
  @Binding var text: String
  let matchCount: Int?
  var focused: FocusState<Bool>.Binding
  var width: CGFloat = 150
  let next: () -> Void
  let close: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(focused.wrappedValue ? Theme.accent : Theme.textMuted)
      TextField("Find in graph", text: $text)
        .textFieldStyle(.plain)
        .font(.geist(12.5))
        .frame(width: width)
        .focused(focused)
        .onSubmit(next)
        .onExitCommand(perform: close)
      if let matchCount {
        Text("\(matchCount)")
          .font(.geistMono(11))
          .foregroundStyle(matchCount == 0 ? Theme.danger : Theme.textSubtle)
      } else {
        Text("⌘F").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 30)
    .glassPanel(
      radius: 9,
      border: focused.wrappedValue ? Theme.accent.opacity(0.45) : Theme.borderStrong.opacity(0.7))
  }
}

/// Play the graph growing: entries appear in the order they were saved.
struct TimelineBar: View {
  let state: TimelineState
  private let speeds: [Double] = [1, 4, 16]

  var body: some View {
    @Bindable var state = state
    HStack(spacing: 12) {
      Button {
        if state.playing {
          state.playing = false
        } else {
          if state.progress >= 1 { state.progress = 0 }
          state.playing = true
        }
      } label: {
        Image(systemName: state.playing ? "pause.fill" : "play.fill")
          .font(.system(size: 11))
          .foregroundStyle(Theme.accent)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .help(state.playing ? "Pause" : "Watch the brain grow")
      .accessibilityLabel(state.playing ? "Pause" : "Play")

      Slider(value: $state.progress, in: 0...1) { editing in
        if editing { state.playing = false }
      }
      .controlSize(.small)
      .tint(Theme.accent)
      .frame(minWidth: 120)
      .accessibilityLabel("Timeline")

      Text(label)
        .font(.geistMono(11))
        .foregroundStyle(Theme.textSubtle)
        .frame(width: 78, alignment: .trailing)

      HStack(spacing: 2) {
        ForEach(speeds, id: \.self) { speed in
          Button("\(Int(speed))×") { state.speed = speed }
            .buttonStyle(.plain)
            .font(.geistMono(11, state.speed == speed ? .medium : .regular))
            .foregroundStyle(state.speed == speed ? Theme.accent : Theme.textSubtle)
            .frame(width: 30, height: 28)
            .background(
              RoundedRectangle(cornerRadius: 7)
                .fill(state.speed == speed ? Theme.accentWash : .clear)
            )
            .contentShape(Rectangle())
            .focusEffectDisabled()
        }
      }
    }
    .padding(.leading, 6)
    .padding(.trailing, 8)
    .frame(height: 40)
    .glassPanel(radius: 12)
  }

  private var label: String {
    guard state.progress < 1 else { return "now" }
    return state.date?.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) ?? "—"
  }
}
