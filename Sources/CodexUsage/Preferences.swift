import AppKit
import SwiftUI

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var interval: Int { didSet { defaults.set(interval, forKey: "refreshInterval") } }
    @Published var topmost: Bool { didSet { defaults.set(topmost, forKey: "topmost") } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    @Published var primaryColorHex: String { didSet { defaults.set(primaryColorHex, forKey: "primaryRingColor") } }
    @Published var secondaryColorHex: String { didSet { defaults.set(secondaryColorHex, forKey: "secondaryRingColor") } }
    @Published var layout: String { didSet { defaults.set(layout, forKey: "layout") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let primary = defaults.string(forKey: "primaryRingColor") ?? Self.defaultPrimaryColor
        let secondary = defaults.string(forKey: "secondaryRingColor") ?? Self.defaultSecondaryColor
        primaryColorHex = Self.color(from: primary) != nil ? primary : Self.defaultPrimaryColor
        secondaryColorHex = Self.color(from: secondary) != nil ? secondary : Self.defaultSecondaryColor
        let stored = defaults.integer(forKey: "refreshInterval")
        interval = [10, 30, 60].contains(stored) ? stored : 30
        topmost = defaults.bool(forKey: "topmost")
        let alpha = defaults.double(forKey: "opacity")
        opacity = defaults.object(forKey: "opacity") != nil && alpha.isFinite && (0...1).contains(alpha) ? alpha : 1
        let theme = defaults.string(forKey: "appearance") ?? "system"
        appearance = ["system", "light", "dark"].contains(theme) ? theme : "system"
        let storedLayout = defaults.string(forKey: "layout") ?? "quota"
        layout = ["quota", "tokens"].contains(storedLayout) ? storedLayout : "quota"
    }
    static let defaultPrimaryColor = "297DFA"
    static let defaultSecondaryColor = "7A63F0"
    var primaryRingColor: NSColor { Self.color(from: primaryColorHex) ?? Self.color(from: Self.defaultPrimaryColor)! }
    var secondaryRingColor: NSColor { Self.color(from: secondaryColorHex) ?? Self.color(from: Self.defaultSecondaryColor)! }
    static func color(from hex: String) -> NSColor? {
        guard hex.count == 6, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }), let rgb = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                       green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
    }
    static func hex(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
    func resetRingColors() {
        primaryColorHex = Self.defaultPrimaryColor
        secondaryColorHex = Self.defaultSecondaryColor
    }
    // Match the system Batteries medium widget: 344×164 card plus 8pt outer inset.
    var cardSize: NSSize { NSSize(width: 344, height: 164) }
    var panelSize: NSSize { NSSize(width: cardSize.width + 16, height: cardSize.height + 16) }
    var colorScheme: ColorScheme? { appearance == "system" ? nil : appearance == "dark" ? .dark : .light }
    func restoreOrigin(size: NSSize) -> NSPoint {
        if let point = defaults.string(forKey: "windowOrigin") {
            let origin = NSPointFromString(point)
            let proposed = NSRect(origin: origin, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(proposed) }) { return origin }
        }
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: frame.maxX - size.width - 28, y: frame.maxY - size.height - 28)
    }
    func saveOrigin(_ origin: NSPoint) { defaults.set(NSStringFromPoint(origin), forKey: "windowOrigin") }
}
