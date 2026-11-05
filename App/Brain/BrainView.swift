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
  @State private var scrollMonitor: Any?

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
              HubLabels(labels: labels, graph: graph)
            }
            Header(graph: graph, focused: selection != nil) {
              setSelection(nil)
            }
            .padding(20)
            if let hovered, hovered < graph.nodes.count, selection != .node(hovered) {
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
          if case .node(let i) = selection, i >= value.nodes.count { setSelection(nil) }
        }
      } catch {}
    }
    .onAppear(perform: startScrollZoom)
    .onDisappear {
      if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
      scrollMonitor = nil
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
    .simultaneousGesture(
      MagnifyGesture().onChanged { value in
        holder.renderer?.zoom(
          by: Float(1 / max(value.magnification, 0.01)).squareRoot().squareRoot())
      }
    )
    .onTapGesture { location in
      switch holder.renderer?.hit(at: location, size: size) {
      case .hub(let projectID): setSelection(.project(projectID))
      case .node(let index): setSelection(.node(index))
      case nil: setSelection(nil)
      }
    }
    .onContinuousHover { phase in
      switch phase {
      case .active(let location):
        pointer = location
        if case .node(let index) = holder.renderer?.hit(at: location, size: size) {
          hover(index)
        } else {
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
  }

  private func setSelection(_ value: BrainSelection?) {
    selection = value
    switch value {
    case .project(let id):
      holder.renderer?.selectedNode = nil
      holder.renderer?.focus(id)
    case .node(let index):
      holder.renderer?.selectedNode = index
      holder.renderer?.focus(graph.nodes[index].projectID)
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

  /// Scroll wheel and trackpad scrolling zoom while the Brain is showing.
  private func startScrollZoom() {
    guard scrollMonitor == nil else { return }
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
      let deltaY = Float(event.scrollingDeltaY)
      let handled = MainActor.assumeIsolated { () -> Bool in
        guard model.section == .brain, !graph.nodes.isEmpty, let renderer = holder.renderer
        else { return false }
        renderer.zoom(by: exp(-deltaY * 0.01))
        return true
      }
      return handled ? nil : event
    }
  }
}

enum BrainSelection: Hashable {
  case project(String)
  case node(Int)
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

  func makeNSView(context: Context) -> MTKView {
    let view = MTKView()
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

  func updateNSView(_ view: MTKView, context: Context) {}
}

/// Project names next to their hubs; the renderer moves them every frame.
private struct HubLabels: View {
  let labels: GraphLabels
  let graph: GraphSnapshot

  var body: some View {
    let names = Dictionary(uniqueKeysWithValues: graph.projects.map { ($0.id, $0) })
    ZStack(alignment: .topLeading) {
      ForEach(labels.items) { label in
        if let project = names[label.id] {
          HStack(spacing: 6) {
            Circle().fill(Color(hexString: project.color)).frame(width: 6, height: 6)
            Text(project.name).font(.geist(12, .medium)).foregroundStyle(Theme.text)
          }
          .padding(.horizontal, 8)
          .frame(height: 22)
          .background(Capsule().fill(Theme.background.opacity(0.72)))
          .overlay(Capsule().stroke(Theme.border))
          .opacity(label.opacity)
          .fixedSize()
          .position(x: label.point.x, y: label.point.y - 26)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(false)
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
      HStack(spacing: 10) {
        Text("Drag to turn · scroll to zoom · click a project")
          .font(.geist(11.5))
          .foregroundStyle(Theme.textSubtle)
        if focused {
          SmallButton(
            title: "Show all", symbol: "arrow.down.right.and.arrow.up.left", action: showAll)
        }
      }
      .padding(.top, 4)
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
