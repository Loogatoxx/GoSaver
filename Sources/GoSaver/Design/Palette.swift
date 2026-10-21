import SwiftUI
import AppKit

/// Encres de la charte « Atlas » (docs/DESIGN_SYSTEM.md §3).
/// Chaque couleur a une version Papier (clair) et Lampe (sombre) ;
/// macOS choisit automatiquement selon l'apparence du système.
enum Ink {
    static let paper       = dynamic(light: 0xF1E9D8, dark: 0x17140F)
    static let paperRaised = dynamic(light: 0xF8F2E6, dark: 0x211C15)
    static let paperSunken = dynamic(light: 0xE6DCC6, dark: 0x100E0A)
    static let ink         = dynamic(light: 0x1E1912, dark: 0xEFE5D0)
    /// Texte secondaire : sépia, jamais gris.
    static let inkFaded    = dynamic(light: 0x5A4630, dark: 0xCDB792)
    /// Courbes de niveau et filets — jamais pour du texte (contraste 3,3 : 1).
    static let contour     = dynamic(light: 0x9C7A52, dark: 0x7A6347)
    static let sea         = dynamic(light: 0x2E5A6E, dark: 0x79A9BD)
    static let seaWash     = dynamic(light: 0xC9D6D3, dark: 0x1B2A2F)
    /// Accent unique : une seule action principale par écran.
    static let vermilion   = dynamic(light: 0xA63412, dark: 0xE46A3E)
    static let forest      = dynamic(light: 0x3F5E2F, dark: 0x9DB77A)
    static let ochre       = dynamic(light: 0x7E500B, dark: 0xD9A54A)

    /// Couleur qui suit l'apparence (clair/sombre) du système.
    /// On passe par NSColor parce que SwiftUI seul ne sait pas déclarer
    /// une couleur à deux variantes sans catalogue d'assets Xcode.
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
