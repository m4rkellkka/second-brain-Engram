import AppKit
import QuartzCore

/// Project and Inbox names over the graph, drawn as plain Core Animation
/// layers inside the Metal view.
///
/// They used to be SwiftUI buttons. Moving twenty of them every frame cost
/// SwiftUI a re-layout per frame (half the frame rate at 10,000 entries),
/// and where a label sat over a very bright cluster the window composited
/// a light rectangle under it. Layers move for almost nothing; clicks and
/// hover go through the renderer's hit test instead.
@MainActor
final class GraphLabelLayer {
  struct Item: Equatable {
    var id: String
    var name: String
    var dot: CGColor
    var muted: Bool
    /// In view points, top-left origin.
    var frame: CGRect
    var opacity: Float
  }

  static let font =
    NSFont(name: "Geist-Medium", size: 12) ?? .systemFont(ofSize: 12, weight: .medium)
  static let height: CGFloat = 22
  private static let padding: CGFloat = 8
  private static let dotSize: CGFloat = 6
  private static let gap: CGFloat = 6

  /// Flipped, so frames use the same top-left points as SwiftUI.
  let root: CALayer = {
    let layer = CALayer()
    layer.isGeometryFlipped = true
    return layer
  }()
  private var boxes: [String: (box: CALayer, dot: CALayer, text: CATextLayer)] = [:]
  private var widths: [String: CGFloat] = [:]
  private var current: [Item] = []

  /// The label's width for a name: padding, dot, gap and the text.
  func width(of name: String) -> CGFloat {
    if let width = widths[name] { return width }
    let text = (name as NSString).size(withAttributes: [.font: Self.font]).width
    let width = (Self.padding * 2 + Self.dotSize + Self.gap + text).rounded(.up)
    widths[name] = width
    return width
  }

  func update(_ items: [Item], bounds: CGRect, scale: CGFloat) {
    guard items != current || root.frame != bounds else { return }
    current = items
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    root.frame = bounds
    var seen: Set<String> = []
    for item in items {
      seen.insert(item.id)
      let parts = boxes[item.id] ?? makeBox(scale: scale)
      boxes[item.id] = parts
      parts.box.frame = item.frame
      parts.box.opacity = item.opacity
      parts.dot.backgroundColor = item.dot
      let textX = Self.padding + Self.dotSize + Self.gap
      parts.text.frame = CGRect(
        x: textX, y: (Self.height - 15) / 2, width: item.frame.width - textX - Self.padding,
        height: 15)
      if parts.text.string as? String != item.name { parts.text.string = item.name }
      parts.text.foregroundColor =
        (item.muted ? NSColor(Theme.textMuted) : NSColor(Theme.text)).cgColor
    }
    for (id, parts) in boxes where !seen.contains(id) {
      parts.box.removeFromSuperlayer()
      boxes[id] = nil
    }
    CATransaction.commit()
  }

  private func makeBox(scale: CGFloat) -> (box: CALayer, dot: CALayer, text: CATextLayer) {
    let box = CALayer()
    box.backgroundColor = NSColor(Theme.background).withAlphaComponent(0.6).cgColor
    box.borderColor = NSColor(Theme.border).cgColor
    box.borderWidth = 1
    box.cornerRadius = Self.height / 2
    let dot = CALayer()
    dot.frame = CGRect(
      x: Self.padding, y: (Self.height - Self.dotSize) / 2, width: Self.dotSize,
      height: Self.dotSize)
    dot.cornerRadius = Self.dotSize / 2
    let text = CATextLayer()
    text.font = Self.font
    text.fontSize = Self.font.pointSize
    text.contentsScale = scale
    text.truncationMode = .end
    box.addSublayer(dot)
    box.addSublayer(text)
    root.addSublayer(box)
    return (box, dot, text)
  }
}
