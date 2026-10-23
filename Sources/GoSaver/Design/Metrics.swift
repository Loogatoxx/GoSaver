import SwiftUI
import AppKit

/// Espacements, traits, rayons et ombres (docs/DESIGN_SYSTEM.md §5).
enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let s8: CGFloat = 64
}

enum Stroke {
    static let hairline: CGFloat = 0.5
    static let rule: CGFloat = 1
    static let ruleStrong: CGFloat = 2
}

enum Radius {
    /// Défaut : cadres, cartouches, panneaux.
    static let none: CGFloat = 0
    /// Boutons et champs. Il n'existe pas de rayon plus grand.
    static let small: CGFloat = 2
}

/// Mouvements (docs/DESIGN_SYSTEM.md §7).
@MainActor
enum Motion {
    /// Réglage « Réduire les animations » de macOS, ou celui de GoSaver :
    /// les fiches apparaissent alors en fondu bref, sans glisser ni rebondir (WCAG 2.3.3).
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || Preferences.shared.reducedAnimations
    }
    static var quick: Animation { .easeOut(duration: 0.12) }
    static var settle: Animation { reduced ? .easeOut(duration: 0.1) : .spring(response: 0.32, dampingFraction: 0.86) }
    static var survey: Animation { reduced ? .easeOut(duration: 0.1) : .easeInOut(duration: 0.9) }
}

extension View {
    /// Ombre de « feuille posée » : courte, dure, lumière en haut à gauche.
    func sheetShadow(lifted: Bool = false) -> some View {
        self.shadow(
            color: Ink.ink.opacity(lifted ? 0.16 : 0.12),
            radius: lifted ? 1 : 0,
            x: lifted ? 2 : 1,
            y: lifted ? 5 : 2
        )
    }
}
