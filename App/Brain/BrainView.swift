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

  var body: some View {
    HStack(spacing: 0) {
      GeometryReader { geometry in
        ZStack(alignment: .topLeading) {
          if graph.nodes.isEmpty {
            EmptyState(
              symbol: "point.3.connected.trianglepath.dotted", title: "Brain",
              text:
                "Your graph appears here as soon as you save something with Claude or the capture field."
            )
          } else {
            canvas(size: geometry.size)
            if let labels = holder.renderer?.labels {
              HubLabels(
                labels: labels, graph: graph,
                select: { setSelection(.project($0)) },
                hover: { holder.renderer?.hoveredProject = $0 })
            }
            // Keeps labels that drift under the header from showing through it.
            LinearGradient(
              stops: [
                .init(color: Theme.background.opacity(0.95), location: 0),
                .init(color: Theme.background.opacity(0.85), location: 0.6),
                .init(color: Theme.background.opacity(0), location: 1),
              ],
              startPoint: .top, endPoint: .bottom
            )
            .frame(height: 170)
            .allowsHitTesting(false)
            Header(graph: graph, focused: selection != nil) {
              setSelection(nil)
            }
            .padding(20)
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
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
              .padding(14)
              .allowsHitTesting(false)
            #endif
          }
        }
      }
      if let selection {
        BrainSidePanel(selection: selection, graph: graph) { setSelection(nil) }
          .frame(width: 320)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .background(Theme.background)
    .animation(.easeOut(duration: 0.25), value: selection)
    .task(id: model.externalChanges) {
      guard let database = model.database else { return }
      do {
        for try await value in database.graphUpdates() {
          let isFirst = graph.nodes.isEmpty
          graph = value
          holder.renderer?.show(value)
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
    MetalGraphView(holder: holder) { renderer in
      renderer.show(graph)
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
      case .hub(let projectID): setSelection(.project(projectID))
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

  private func hover(_ index: Int?) {
    hovered = index
    holder.renderer?.hoveredNode = index
    holder.renderer?.hoveredProject = nil
  }

  private func setSelection(_ value: BrainSelection?) {
    selection = value
    switch value {
    case .project(let id):
      holder.renderer?.selectedNode = nil
      holder.renderer?.focus(id)
    case .node(let id):
      let index = holder.renderer?.index(of: id)
      holder.renderer?.selectedNode = index
      holder.renderer?.focus(index.flatMap { graph.nodes[$0].projectID })
    case nil:
      holder.renderer?.selectedNode = nil
      holder.renderer?.focus(nil)
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
  let onReady: (GraphRenderer) -> Void

  func makeNSView(context: Context) -> GraphMTKView {
    let view = GraphMTKView()
    view.onZoom = { [holder] factor in holder.renderer?.zoom(by: factor) }
    view.colorPixelFormat = .bgra8Unorm
    view.sampleCount = 4
    view.clearColor = MTLClearColor(red: 0x09 / 255, green: 0x09 / 255, blue: 0x0B / 255, alpha: 1)
    view.preferredFramesPerSecond = 120
    view.layer?.isOpaque = true
    if let renderer = GraphRenderer(view: view) {
      holder.renderer = renderer
      onReady(renderer)
    }
    return view
  }

  func updateNSView(_ view: GraphMTKView, context: Context) {}
}

/// The graph's Metal view. Scrolling and pinching zoom only while the
/// pointer is over the graph (so the side panel still scrolls), and drawing
/// pauses while the window can't be seen, e.g. closed to the menu bar.
final class GraphMTKView: MTKView {
  var onZoom: ((Float) -> Void)?
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
  }

  @objc private func occlusionChanged() {
    isPaused = !(window?.occlusionState.contains(.visible) ?? false)
  }
}

/// Project names above their hubs; the renderer moves them every frame.
/// Clicking a name focuses the project, hovering lights it up.
private struct HubLabels: View {
  let labels: GraphLabels
  let graph: GraphSnapshot
  let select: (String) -> Void
  let hover: (String?) -> Void

  var body: some View {
    let names = Dictionary(
      graph.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    ZStack(alignment: .topLeading) {
      ForEach(labels.items) { label in
        if let project = names[label.id] {
          Button {
            select(project.id)
          } label: {
            HStack(spacing: 6) {
              Circle().fill(Color(hexString: project.color)).frame(width: 6, height: 6)
              Text(project.name).font(.geist(12, .medium)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Theme.background.opacity(0.6)))
            .overlay(Capsule().stroke(Theme.border))
            .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .focusEffectDisabled()
          .onHover { inside in hover(inside ? project.id : nil) }
          .accessibilityLabel("Focus \(project.name)")
          .opacity(label.opacity)
          .fixedSize()
          .position(x: label.point.x, y: label.point.y - label.lift)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct Header: View {
  let graph: GraphSnapshot
  let focused: Bool
  let showAll: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Your brain").font(.geist(20, .semibold)).foregroundStyle(Theme.text)
      Text(
        "\(graph.nodes.count) entries · \(graph.links.count) links · \(graph.projects.count) projects"
      )
      .font(.geistMono(11))
      .foregroundStyle(Theme.textSubtle)
      .lineLimit(1)
      // The hint shrinks, then hides, when the side panel leaves less room.
      ViewThatFits(in: .horizontal) {
        hintRow("Drag to turn · scroll to zoom · click a project")
        hintRow("Drag · scroll · click")
        hintRow(nil)
      }
      .padding(.top, 4)
    }
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
        KindBadge(kind: node.kind)
        if let project {
          Circle().fill(Color(hexString: project.color)).frame(width: 6, height: 6)
          Text(project.name).font(.geist(11.5)).foregroundStyle(Theme.textMuted)
        }
      }
      Text(node.content).font(.geist(13)).foregroundStyle(Theme.text).lineLimit(3)
    }
    .padding(10)
    .frame(width: 280, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface2.opacity(0.96))
    )
    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.borderStrong))
  }
}

#Preview("Brain") {
  BrainView()
    .environment(AppModel.preview())
    .frame(width: 1000, height: 680)
    .preferredColorScheme(.dark)
}
