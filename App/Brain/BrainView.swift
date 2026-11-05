import AppKit
import EngramKit
import RealityKit
import SwiftUI

/// The 3D graph of every entry, clustered by project.
struct BrainView: View {
  @Environment(AppModel.self) private var model
  @State private var scene = GraphScene()
  @State private var graph = GraphSnapshot.empty
  @State private var updates: EventSubscription?
  @State private var hovered: Int?
  @State private var pointer: CGPoint = .zero
  @State private var dragStart: CGSize = .zero
  @State private var fps: Double = 0
  @State private var lastFPSUpdate = Date.distantPast
  #if DEBUG
    /// `-EngramGraphMarkers YES`: hold still and ring the projected hubs, to
    /// check that hover and click land where the scene draws.
    private let showMarkers = UserDefaults.standard.bool(forKey: "EngramGraphMarkers")
  #endif
  @State private var scrollMonitor: Any?

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        if graph.nodes.isEmpty {
          EmptyState(
            symbol: "point.3.connected.trianglepath.dotted",
            title: "Brain",
            text:
              "Your graph appears here as soon as you save something with Claude or the capture field."
          )
        } else {
          sceneView(size: geometry.size)
          Legend(graph: graph)
            .padding(20)
          if let hovered, hovered < graph.nodes.count {
            HoverLabel(node: graph.nodes[hovered], project: scene.project(for: hovered))
              .position(labelPosition(in: geometry.size))
              .allowsHitTesting(false)
          }
          #if DEBUG
            if showMarkers { HubMarkers(scene: scene, size: geometry.size) }
            Text("\(Int(fps.rounded())) fps")
              .font(.geistMono(11))
              .foregroundStyle(Theme.textSubtle)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
              .padding(14)
              .allowsHitTesting(false)
          #endif
        }
      }
    }
    .background(Theme.background)
    .task(id: model.externalChanges) {
      guard let database = model.database else { return }
      do {
        for try await value in database.graphUpdates() {
          graph = value
          scene.show(value)
        }
      } catch {}
    }
    .onAppear {
      startScrollZoom()
      #if DEBUG
        if showMarkers { scene.autoRotate = false }
      #endif
    }
    .onDisappear {
      if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
      scrollMonitor = nil
    }
  }

  private func sceneView(size: CGSize) -> some View {
    RealityView { content in
      content.add(scene.root)
      content.add(scene.camera)
      updates = content.subscribe(to: SceneEvents.Update.self) { event in
        let delta = event.deltaTime
        MainActor.assumeIsolated {
          scene.tick(delta)
          // Updating SwiftUI state every frame would re-render the overlay
          // 60 times a second; twice a second is enough for the counter.
          if Date().timeIntervalSince(lastFPSUpdate) > 0.5 {
            lastFPSUpdate = Date()
            fps = scene.framesPerSecond
          }
        }
      }
    }
    .gesture(
      DragGesture(minimumDistance: 3)
        .onChanged { value in
          let step = CGSize(
            width: value.translation.width - dragStart.width,
            height: value.translation.height - dragStart.height)
          dragStart = value.translation
          scene.rotate(by: step)
          hovered = nil
        }
        .onEnded { _ in dragStart = .zero }
    )
    .simultaneousGesture(
      MagnifyGesture().onChanged { value in
        scene.zoom(by: Float(1 / max(value.magnification, 0.01)).squareRoot().squareRoot())
      }
    )
    .onTapGesture { location in
      guard let index = scene.node(at: location, in: size) else { return }
      if let project = scene.project(for: index) {
        model.openProject(project.id)
      } else {
        model.section = .inbox
      }
    }
    .onContinuousHover { phase in
      switch phase {
      case .active(let location):
        pointer = location
        hovered = scene.node(at: location, in: size)
      case .ended:
        hovered = nil
      }
    }
  }

  private func labelPosition(in size: CGSize) -> CGPoint {
    let x = min(max(pointer.x + 150, 160), size.width - 160)
    let y = min(max(pointer.y - 36, 40), size.height - 40)
    return CGPoint(x: x, y: y)
  }

  /// Scroll wheel and trackpad scrolling zoom while the pointer is over the graph.
  private func startScrollZoom() {
    guard scrollMonitor == nil else { return }
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
      let deltaY = Float(event.scrollingDeltaY)
      let handled = MainActor.assumeIsolated { () -> Bool in
        guard model.section == .brain, !graph.nodes.isEmpty else { return false }
        scene.zoom(by: exp(-deltaY * 0.01))
        return true
      }
      return handled ? nil : event
    }
  }
}

#if DEBUG
  private struct HubMarkers: View {
    let scene: GraphScene
    let size: CGSize

    var body: some View {
      Canvas { context, _ in
        for hub in scene.layout.hubs.values {
          guard let (point, _) = scene.project(hub, in: size) else { continue }
          let ring = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
          context.stroke(Path(ellipseIn: ring), with: .color(.red), lineWidth: 1.5)
        }
      }
      .allowsHitTesting(false)
    }
  }
#endif

private struct Legend: View {
  let graph: GraphSnapshot

  var body: some View {
    let counts = Dictionary(grouping: graph.nodes, by: \.projectID).mapValues(\.count)
    VStack(alignment: .leading, spacing: 6) {
      Text("Brain").font(.geist(17, .semibold)).foregroundStyle(Theme.text)
      Text("\(graph.nodes.count) entries · \(graph.links.count) links")
        .font(.geistMono(11))
        .foregroundStyle(Theme.textSubtle)
        .padding(.bottom, 4)
      ForEach(graph.projects.filter { counts[$0.id] != nil }) { project in
        HStack(spacing: 8) {
          Circle().fill(Color(hexString: project.color)).frame(width: 7, height: 7)
          Text(project.name).font(.geist(12)).foregroundStyle(Theme.textMuted)
          Text("\(counts[project.id] ?? 0)").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
        }
      }
      if let unfiled = counts[nil] {
        HStack(spacing: 8) {
          Circle().fill(Theme.textSubtle).frame(width: 7, height: 7)
          Text("No project").font(.geist(12.5)).foregroundStyle(Theme.textMuted)
          Text("\(unfiled)").font(.geistMono(11)).foregroundStyle(Theme.textSubtle)
        }
      }
      Text("Drag to turn · scroll to zoom · click to open")
        .font(.geist(11.5))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Theme.textSubtle)
        .padding(.top, 6)
    }
    .padding(12)
    .frame(width: 230, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.sidebar.opacity(0.55)))
    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
    .allowsHitTesting(false)
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
      Text(node.content)
        .font(.geist(13))
        .foregroundStyle(Theme.text)
        .lineLimit(3)
    }
    .padding(10)
    .frame(width: 280, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface2))
    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.borderStrong))
  }
}

#Preview("Brain") {
  BrainView()
    .environment(AppModel.preview())
    .frame(width: 900, height: 640)
    .preferredColorScheme(.dark)
}
