import AppKit
import SwiftUI

/// Design tokens: the dark "constellation" style (near-black ground, glass
/// panels with a cool border, cyan accent). Dark theme only.
enum Theme {
  static let background = Color(hex: 0x05060B)
  /// The tint over a glass panel's blur.
  static let glass = Color(hex: 0x0E101C).opacity(0.78)
  /// Quiet cards that sit on the background rather than float over it.
  static let surface = Color.white.opacity(0.035)
  static let surface2 = Color.white.opacity(0.06)
  static let border = Color(hex: 0x96AAFF).opacity(0.10)
  static let borderStrong = Color(hex: 0x96AAFF).opacity(0.20)
  static let text = Color(hex: 0xE8ECF8)
  static let textMuted = Color(hex: 0xA3ABC4)
  static let textSubtle = Color(hex: 0x8790AA)
  static let accent = Color(hex: 0x67E8F9)
  static let onAccent = Color(hex: 0x04131A)
  /// Selected tabs and chips: a faint wash of the accent.
  static let accentWash = Color(hex: 0x67E8F9).opacity(0.13)
  static let danger = Color(hex: 0xF48FB1)

  static let controlRadius: CGFloat = 10
  static let cardRadius: CGFloat = 18

  /// Kind colors, from the project palette.
  static func kindColor(_ kind: String) -> Color {
    switch kind {
    case "idea": Color(hex: 0xB79CFF)
    case "task": Color(hex: 0xF2A65A)
    case "link": Color(hex: 0x7FA8FF)
    default: Color(hex: 0x3FD0B6)
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }

  /// `#RRGGBB` from the database, or the accent color if it doesn't parse.
  init(hexString: String) {
    let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
    if digits.count == 6, let value = UInt32(digits, radix: 16) {
      self.init(hex: value)
    } else {
      self = Theme.accent
    }
  }
}

extension Font {
  static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    let name =
      switch weight {
      case .medium: "Geist-Medium"
      case .semibold, .bold: "Geist-SemiBold"
      default: "Geist-Regular"
      }
    return .custom(name, size: size)
  }

  static func geistMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom(weight == .regular ? "GeistMono-Regular" : "GeistMono-Medium", size: size)
  }
}

/// Registers the bundled Geist fonts for this process.
enum Fonts {
  static func register() {
    guard
      let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil),
      !urls.isEmpty
    else { return }
    CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
  }
}
