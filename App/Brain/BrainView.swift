import AppKit
import EngramKit
import MetalKit
import Observation
import SwiftUI

/// The 3D graph of every entry, clustered by project.
struct BrainView: View {
  @Environment(AppModel.self) private var model
  @State private var holder = RendererHolder()
  @State private var graph = GraphSnapshot.empty
  @State private var pointer: CGPoint = .zero
  @State private var hovered: Int?
  @State private var dragStart: CGSize = .zero
  @State private var selection: BrainSelection?
  @State private var filter = GraphFilter()
  @State private var searchText = ""
  @State private var matches: [String]?
  @State private var matchCursor = 0
  @FocusState private var searchFocused: Bool
  /// Nodes visited with Tab, so ⇧Tab can walk back.
  @State private var walk: [String] = []

  var body: some View {
    HStack(spacing: 0) {
      GeometryReader { geometry in
        ZStack(alignment: .topLeading) {
          if graph.nodes.isEmpty {
            EmptyState(
              symbol: "point.3.connected.trianglepath.dotted", title: "Your brain is still quiet",
              text:
                "The graph lights up as soon as you save something with Claude or the capture field."
            )
          } else {
            canvas(size: geometry.size)
            // Glass header: labels drifting under it blur instead of
            // showing through.
            // Header on the left, search and filter on the right; the
            // search field narrows before the two would touch.
            HStack(alignment: .top, spacing: 12) {
              Header(graph: graph, focused: selection != nil) {
                setSelection(nil)
              }
              Spacer(minLength: 0)
              ViewThatFits(in: .horizontal) {
                controls(fieldWidth: 150)
                controls(fieldWidth: 90)
              }
            }
            .padding(20)
            VStack(alignment: .leading, spacing: 10) {
              ProjectLegend(projects: graph.projects, focused: focusedProject) { id in
                setSelection(id == focusedProject ? nil : .project(id))
              }
              if let renderer = holder.renderer {
                TimelineBar(state: renderer.timelineState).frame(maxWidth: 560)
              }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            // ⌘F focuses the graph's search field.
            Button("Find in graph") { searchFocused = true }
              .keyboardShortcut("f")
              .hidden()
            if let hovered, hovered < graph.nodes.count,
              selection != .node(graph.nodes[hovered].id)
            {
              HoverLabel(node: graph.nodes[hovered], project: project(of: hovered))
                .position(labelPosition(in: geometry.size))
                .allowsHitTesting(false)
            }
            #if DEBUG
              TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text("\(Int((holder.renderer?.framesPerSecond ?? 0).rounded())) fps")
                  .font(.geistMono(11))
                  .foregroundStyle(Theme.textSubtle)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
              .padding(.top, 62)
              .padding(.trailing, 24)
              .allowsHitTesting(false)
            #endif
          }
        }
      }
      if let selection {
        BrainSidePanel(
          selection: selection, graph: graph,
          select: { value in
            setSelection(value)
            if case .node(let id) = value, let index = holder.renderer?.index(of: id) {
              holder.renderer?.aim(at: index)
            }
          }
        ) { setSelection(nil) }
        .frame(width: 320)
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .background(Theme.background)
    .animation(.easeOut(duration: 0.25), value: selection)
    .onChange(of: filter) { applyFilterAndSearch() }
    .task(id: searchText) {
      let text = searchText.trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty, let database = model.database else {
        matches = nil
        holder.renderer?.setSearch(nil)
        return
      }
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      let ids =
        (try? await database.writer.read { try AppDatabase.graphMatches($0, query: text) })
        ?? []
      holder.renderer?.setSearch(ids)
      matches = graph.nodes.indices.reversed().compactMap { i in
        ids.contains(graph.nodes[i].id) && holder.renderer?.isDrawn(i) == true
          ? graph.nodes[i].id : nil
      }
      matchCursor = 0
    }
    .task(id: model.externalChanges) {
      guard let database = model.database else { return }
      do {
        for try await value in database.graphUpdates() {
          let isFirst = graph.nodes.isEmpty
          graph = value
          holder.renderer?.show(value)
          applyFilterAndSearch()
          #if DEBUG
            // `-EngramFocusProject <slug>`: open focused on a project, for screenshots.
            if isFirst, let slug = UserDefaults.standard.string(forKey: "EngramFocusProject"),
              let project = value.projects.first(where: { $0.slug == slug })
            {
              holder.renderer?.autoRotate = false
              setSelection(.project(project.id))
            }

          #endif
          // "Show in Brain" on a project page asked to fly to a project.
          if let id = model.brainFocusRequest, value.projects.contains(where: { $0.id == id }) {
            model.brainFocusRequest = nil
            setSelection(.project(id))
          }
          // Indexes may mean other entries now; selection is kept by id.
          hover(nil)
          if case .node(let id) = selection, holder.renderer?.index(of: id) == nil {
            setSelection(nil)
          } else {
            setSelection(selection)
          }
        }
      } catch {}
    }
  }

  private func canvas(size: CGSize) -> some View {
    MetalGraphView(holder: holder, onKey: handle) { renderer in
      renderer.show(graph)
      renderer.setFilter(filter.visibility(for: graph))
      #if DEBUG
        // `-EngramPlayTimeline 16`: play the timeline at that speed, to
        // measure the frame rate while the graph grows.
        let speed = UserDefaults.standard.double(forKey: "EngramPlayTimeline")
        if speed > 0 {
          renderer.timelineState.speed = speed
          renderer.timelineState.progress = 0
          renderer.timelineState.playing = true
        }
        // `-EngramGraphSearch <text>`: open with a ⌘F search filled in.
        if let text = UserDefaults.standard.string(forKey: "EngramGraphSearch") {
          // Not during the view update that created the renderer.
          Task { @MainActor in searchText = text }
        }
      #endif
      // The view appears after the first graph arrived, so apply whatever
      // was selected before the renderer existed.
      setSelection(selection)
    }
    .gesture(
      DragGesture(minimumDistance: 3)
        .onChanged { value in
          let step = CGSize(
            width: value.translation.width - dragStart.width,
            height: value.translation.height - dragStart.height)
          dragStart = value.translation
          holder.renderer?.orbit(by: step)
          hover(nil)
        }
        .onEnded { _ in dragStart = .zero }
    )
    .onTapGesture { location in
      switch holder.renderer?.hit(at: location, size: size) {
      case .hub(let id): setSelection(id == GraphRenderer.inboxID ? .inbox : .project(id))
      case .node(let index): setSelection(.node(graph.nodes[index].id))
      case nil: setSelection(nil)
      }
    }
    .onContinuousHover { phase in
      switch phase {
      case .active(let location):
        pointer = location
        switch holder.renderer?.hit(at: location, size: size) {
        case .node(let index):
          hover(index)
        case .hub(let projectID):
          hover(nil)
          holder.renderer?.hoveredProject = projectID
        case nil:
          hover(nil)
        }
      case .ended:
        hover(nil)
      }
    }
  }

  private func controls(fieldWidth: CGFloat) -> some View {
    HStack(spacing: 8) {
      GraphSearchField(
        text: $searchText, matchCount: matches?.count, focused: $searchFocused,
        width: fieldWidth, next: nextMatch, close: closeSearch)
      FilterButton(filter: $filter, projects: graph.projects)
    }
    .fixedSize()
  }

  private func hover(_ index: Int?) {
    hovered = index
    holder.renderer?.hoveredNode = index
    holder.renderer?.hoveredProject = nil
  }

  private func setSelection(_ value: BrainSelection?, walking: Bool = false) {
    selection = value
    if !walking {
      if case .node(let id) = value { walk = [id] } else { walk = [] }
    }
    switch value {
    case .project(let id):
      holder.renderer?.selectedNode = nil
      holder.renderer?.focus(id)
    case .inbox:
      holder.renderer?.selectedNode = nil
      holder.renderer?.focus(GraphRenderer.inboxID)
    case .node(let id):
      let index = holder.renderer?.index(of: id)
      holder.renderer?.selectedNode = index
      holder.renderer?.focus(index.flatMap { holder.renderer?.group(of: $0) })
    case nil:
      holder.renderer?.selectedNode = nil
      holder.renderer?.focus(nil)
    }
  }

  /// The project (or the Inbox) the camera is on, from any selection.
  private var focusedProject: String? {
    switch selection {
    case .project(let id): id
    case .inbox: GraphRenderer.inboxID
    case .node(let id): holder.renderer?.index(of: id).flatMap { holder.renderer?.group(of: $0) }
    case nil: nil
    }
  }

  private func applyFilterAndSearch() {
    holder.renderer?.setFilter(filter.visibility(for: graph))
    // A selected node the filter just hid can't stay selected.
    if case .node(let id) = selection, let index = holder.renderer?.index(of: id),
      holder.renderer?.isDrawn(index) == false
    {
      setSelection(nil)
    }
  }

  // MARK: Search and keyboard

  private func nextMatch() {
    guard let matches, !matches.isEmpty else { return }
    let id = matches[matchCursor % matches.count]
    matchCursor += 1
    select(id, walking: false)
  }

  private func closeSearch() {
    searchText = ""
    searchFocused = false
  }

  /// Selects a node and flies to it.
  private func select(_ id: String, walking: Bool) {
    setSelection(.node(id), walking: walking)
    if let index = holder.renderer?.index(of: id) { holder.renderer?.aim(at: index) }
  }

  private func handle(_ key: GraphKey) -> Bool {
    guard let renderer = holder.renderer, !graph.nodes.isEmpty else { return false }
    switch key {
    case .escape:
      if !searchText.isEmpty {
        closeSearch()
      } else if selection != nil {
        setSelection(nil)
      } else {
        return false
      }
    case .turn(let step):
      renderer.orbit(by: step)
    case .zoomIn:
      renderer.zoom(by: 0.8)
    case .zoomOut:
      renderer.zoom(by: 1.25)
    case .fit:
      setSelection(nil)
    case .project(let number):
      guard number >= 1, number <= graph.projects.count else { return false }
      setSelection(.project(graph.projects[number - 1].id))
    case .next:
      walkForward(renderer)
    case .previous:
      guard walk.count >= 2 else { return false }
      walk.removeLast()
      if let id = walk.last { select(id, walking: true) }
    case .open:
      open()
    }
    return true
  }

  /// Tab: on to the strongest neighbour not visited yet, or to the most
  /// linked node nobody visited when the neighbours run out.
  private func walkForward(_ renderer: GraphRenderer) {
    let visited = Set(walk)
    var next: Int?
    if case .node(let id) = selection, let index = renderer.index(of: id) {
      next = renderer.drawnNeighbours(of: index).first { !visited.contains(graph.nodes[$0].id) }
    }
    if next == nil {
      let group = focusedProject
      next = graph.nodes.indices
        .filter {
          renderer.isDrawn($0) && !visited.contains(graph.nodes[$0].id)
            && (group == nil || renderer.group(of: $0) == group)
        }
        .max {
          (renderer.drawnNeighbours(of: $0).count, -$0)
            < (renderer.drawnNeighbours(of: $1).count, -$1)
        }
    }
    guard let next else { return }
    walk.append(graph.nodes[next].id)
    select(graph.nodes[next].id, walking: true)
  }

  /// Return: opens what is selected, in its own tab.
  private func open() {
    switch selection {
    case .project(let id):
      model.openProject(id)
    case .inbox:
      model.section = .inbox
    case .node(let id):
      guard let node = graph.nodes.first(where: { $0.id == id }) else { return }
      if let day = node.journalDay {
        model.openJournal(day == JournalDate.key(Date()) ? nil : day)
      } else if let project = node.projectID {
        model.openProject(project)
      } else {
        model.section = .inbox
      }
    case nil:
      break
    }
  }

  private func project(of index: Int) -> Project? {
    graph.nodes[index].projectID.flatMap { id in graph.projects.first { $0.id == id } }
  }

  private func labelPosition(in size: CGSize) -> CGPoint {
    CGPoint(
      x: min(max(pointer.x + 156, 160), size.width - 160),
      y: min(max(pointer.y - 40, 44), size.height - 44))
  }

}

enum BrainSelection: Hashable {
  case project(String)
  /// The cloud of entries not filed in any project.
  case inbox
  /// An entry, by id: indexes change whenever the graph updates.
  case node(String)
}

/// Keeps the renderer alive across SwiftUI updates; observable so the
/// overlay appears once the renderer exists.
@Observable
@MainActor
final class RendererHolder {
  var renderer: GraphRenderer?
}

/// MTKView in SwiftUI. MSAA 4x keeps the thin lines smooth.
struct MetalGraphView: NSViewRepresentable {
  let holder: RendererHolder
  let onKey: (GraphKey) -> Bool
  let onReady: (GraphRenderer) -> Void

  func makeNSView(context: Context) -> GraphMTKView {
    let view = GraphMTKView()
    view.onZoom = { [holder] factor in holder.renderer?.zoom(by: factor) }
    view.onKey = onKey
    view.colorPixelFormat = .bgra8Unorm
    view.sampleCount = 4
    view.clearColor = MTLClearColor(red: 0x05 / 255, green: 0x06 / 255, blue: 0x0B / 255, alpha: 1)
    view.preferredFramesPerSecond = 120
    view.layer?.isOpaque = true
    if let renderer = GraphRenderer(view: view) {
      holder.renderer = renderer
      onReady(renderer)
    }
    return view
  }

  func updateNSView(_ view: GraphMTKView, context: Context) { view.onKey = onKey }
}

/// What a key does in the Brain.
enum GraphKey: Equatable {
  case escape, zoomIn, zoomOut, fit, next, previous, open
  case turn(CGSize)
  /// 1…9: focus that project in the legend's order.
  case project(Int)

  /// Plain keys only; anything with ⌘, ⌃ or ⌥ stays a menu shortcut.
  /// Arrows, +/− and Tab go by key code, so they work in any layout.
  init?(_ event: NSEvent) {
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
      return nil
    }
    switch event.keyCode {
    case 53: self = .escape
    case 123: self = .turn(CGSize(width: -40, height: 0))
    case 124: self = .turn(CGSize(width: 40, height: 0))
    case 126: self = .turn(CGSize(width: 0, height: -30))
    case 125: self = .turn(CGSize(width: 0, height: 30))
    case 24, 69: self = .zoomIn
    case 27, 78: self = .zoomOut
    case 48: self = event.modifierFlags.contains(.shift) ? .previous : .next
    case 36, 76: self = .open
    default:
      guard let character = event.charactersIgnoringModifiers?.first,
        let digit = character.wholeNumberValue
      else { return nil }
      self = digit == 0 ? .fit : .project(digit)
    }
  }
}

/// The graph's Metal view. Scrolling and pinching zoom only while the
/// pointer is over the graph (so the side panel still scrolls), and drawing
/// pauses while the window can't be seen, e.g. closed to the menu bar.
final class GraphMTKView: MTKView {
  var onZoom: ((Float) -> Void)?
  var onKey: ((GraphKey) -> Bool)?
  private var keyMonitor: Any?
  /// SwiftUI's gesture layer sits on top of this view and takes scroll
  /// events first, so a local monitor watches them and keeps only those
  /// over the graph.
  private var monitor: Any?

  private func zoom(for event: NSEvent) -> Float? {
    switch event.type {
    case .scrollWheel:
      // A mouse wheel moves in lines, a trackpad in points.
      let deltaY = Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 8)
      return exp(-deltaY * 0.01)
    case .magnify:
      // `magnification` is the change since the last event, not a total.
      return 1 / (1 + max(Float(event.magnification), -0.9))
    default:
      return nil
    }
  }

  private func isOverGraph(_ event: NSEvent) -> Bool {
    guard event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
    return bounds.contains(convert(event.locationInWindow, from: nil))
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    super.viewWillMove(toWindow: newWindow)
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    NotificationCenter.default.addObserver(
      self, selector: #selector(occlusionChanged),
      name: NSWindow.didChangeOcclusionStateNotification, object: window)
    occlusionChanged()
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) {
      [weak self] event in
      // NSEvent isn't Sendable, so only a Bool leaves the main-actor block.
      let handled = MainActor.assumeIsolated { () -> Bool in
        guard let self, self.isOverGraph(event), let factor = self.zoom(for: event) else {
          return false
        }
        self.onZoom?(factor)
        return true
      }
      return handled ? nil : event
    }
    // Keys reach the graph unless a text field (⌘F) is being typed in.
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let handled = MainActor.assumeIsolated { () -> Bool in
        guard let self, let window = self.window, event.window === window, window.isKeyWindow,
          !self.isHiddenOrHasHiddenAncestor, !(window.firstResponder is NSText),
          let key = GraphKey(event)
        else { return false }
        return self.onKey?(key) ?? false
      }
      return handled ? nil : event
    }
  }

  @objc private func occlusionChanged() {
    isPaused = !(window?.occlusionState.contains(.visible) ?? false)
  }
}

private struct Header: View {
  let graph: GraphSnapshot
  let focused: Bool
  let showAll: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Your brain").font(.geist(18, .semibold)).foregroundStyle(Theme.text)
      Text(
        "\(graph.nodes.count(where: { !$0.isJournal })) entries · \(graph.links.count) links · \(graph.projects.count) projects"
      )
      .font(.geistMono(11))
      .foregroundStyle(Theme.textSubtle)
      .lineLimit(1)
      // The hint shrinks, then hides, when the side panel leaves less room.
      ViewThatFits(in: .horizontal) {
        hintRow("Drag or arrows to turn · +/− zoom · Tab walks links")
        hintRow("Drag · scroll · Tab")
        hintRow(nil)
      }
      .padding(.top, 4)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .glassPanel(radius: 16)
  }

  private func hintRow(_ hint: String?) -> some View {
    HStack(spacing: 10) {
      if let hint {
        Text(hint)
          .font(.geist(11.5))
          .foregroundStyle(Theme.textSubtle)
          .lineLimit(1)
          .fixedSize()
      }
      if focused {
        SmallButton(
          title: "Show all", symbol: "arrow.down.right.and.arrow.up.left", action: showAll)
      }
    }
  }
}

private struct HoverLabel: View {
  let node: GraphSnapshot.Node
  let project: Project?

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 6) {
        if node.isJournal {
          JournalBadge(date: node.createdAt)
        } else {
          KindBadge(kind: node.kind)
        }
        if let project {
          Circle().fill(Color(hexString: project.color)).frame(width: 6, height: 6)
          Text(project.name).font(.geist(11.5)).foregroundStyle(Theme.textMuted)
        }
      }
      Text(node.content).font(.geist(13)).foregroundStyle(Theme.text).lineLimit(3)
    }
    .padding(12)
    .frame(width: 280, alignment: .leading)
    .glassPanel(radius: 12)
  }
}

/// Project chips along the bottom; a click flies to the project (or back).
private struct ProjectLegend: View {
  let projects: [Project]
  let focused: String?
  let select: (String) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      chips
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var chips: some View {
    HStack(spacing: 6) {
      ForEach(projects) { project in
        let isFocused = project.id == focused
        Button {
          select(project.id)
        } label: {
          HStack(spacing: 6) {
            Circle().fill(Color(hexString: project.color)).frame(width: 7, height: 7)
            Text(project.name).font(.geist(12.5)).lineLimit(1).fixedSize()
          }
          .foregroundStyle(isFocused ? Theme.text : Theme.textMuted)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .background(Capsule().fill(isFocused ? Theme.accentWash : Theme.glass))
          .overlay(
            Capsule().strokeBorder(
              isFocused ? Theme.accent.opacity(0.45) : Theme.borderStrong.opacity(0.7))
          )
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel("Focus \(project.name)")
      }
    }
  }
}

#Preview("Brain") {
  BrainView()
    .environment(AppModel.preview())
    .frame(width: 1000, height: 680)
    .preferredColorScheme(.dark)
}
