import AppKit
import SwiftUI

/// Design tokens from the mockups. Dark theme only.
enum Theme {
  static let background = Color(hex: 0x09090B)
  static let sidebar = Color(hex: 0x0C0C0F)
  static let surface = Color(hex: 0x121216)
  static let surface2 = Color(hex: 0x18181D)
  static let border = Color(hex: 0x1F1F25)
  static let borderStrong = Color(hex: 0x2A2A32)
  static let text = Color(hex: 0xEDEDF0)
  static let textMuted = Color(hex: 0xA9A9B3)
  static let textSubtle = Color(hex: 0x8E8E99)
  static let accent = Color(hex: 0x8B9CFF)
  static let onAccent = Color(hex: 0x0B0B12)
  static let danger = Color(hex: 0xF48FB1)

  static let controlRadius: CGFloat = 10
  static let cardRadius: CGFloat = 18

  /// Kind badge colors, from the project palette.
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
