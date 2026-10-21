import SwiftUI
import AppKit
import CoreText

/// Les trois voix de la carte (docs/DESIGN_SYSTEM.md §4) :
/// gravure (Newsreader), toponymes (Archivo), cotes (IBM Plex Mono).
enum Typo {
    static var display: Font     { engraving(56, weight: 300, opticalSize: 72) }
    static var title: Font       { engraving(28, weight: 400, opticalSize: 36) }
    static var heading: Font     { engraving(19, weight: 500, opticalSize: 16) }
    static var water: Font       { engraving(15, weight: 400, opticalSize: 15, italic: true) }
    static var region: Font      { toponym(11, weight: 600, width: 112) }
    static var body: Font        { toponym(13, weight: 400, width: 100) }
    static var bodyStrong: Font  { toponym(13, weight: 600, width: 100) }
    static var label: Font       { toponym(11, weight: 500, width: 100) }
    static var figure: Font      { survey(13, medium: true) }
    static var figureLarge: Font { survey(22, medium: false) }

    /// Approche (espacement des lettres) des toponymes en capitales : +18 %.
    static let regionTracking: CGFloat = 11 * 0.18

    // MARK: - Construction

    private static func engraving(_ size: CGFloat, weight: CGFloat, opticalSize: CGFloat, italic: Bool = false) -> Font {
        variable("Newsreader", size: size,
                 axes: ["wght": weight, "opsz": opticalSize], italic: italic,
                 fallback: .system(size: size, design: .serif).italic(italic))
    }

    private static func toponym(_ size: CGFloat, weight: CGFloat, width: CGFloat) -> Font {
        variable("Archivo", size: size, axes: ["wght": weight, "wdth": width],
                 fallback: .system(size: size))
    }

    private static func survey(_ size: CGFloat, medium: Bool) -> Font {
        let name = medium ? "IBMPlexMono-Medium" : "IBMPlexMono"
        guard let font = NSFont(name: name, size: size) else {
            return .system(size: size, design: .monospaced).monospacedDigit()
        }
        return Font(font).monospacedDigit()
    }

    /// Fabrique une police variable en réglant ses axes (graisse, chasse, taille optique).
    /// SwiftUI ne sait régler que la graisse ; CoreText, lui, accède à tous les axes.
    private static func variable(_ family: String, size: CGFloat, axes: [String: CGFloat],
                                 italic: Bool = false, fallback: Font) -> Font {
        let variations = Dictionary(uniqueKeysWithValues: axes.map { (fourCharCode($0.key), $0.value) })
        // L'italique de Newsreader est un fichier à part de la même famille :
        // on le demande par le trait « italique », pas par son nom.
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family,
            kCTFontTraitsAttribute: [kCTFontSymbolicTrait: italic ? CTFontSymbolicTraits.traitItalic.rawValue : 0],
            kCTFontVariationAttribute: variations,
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        // Si la police n'est pas chargée, CoreText renvoie une police de secours : on le détecte.
        guard (CTFontCopyFamilyName(font) as String) == family else {
            return fallback
        }
        return Font(font as NSFont)
    }

    /// « wght » → 0x77676874 : CoreText identifie les axes par ce code numérique.
    private static func fourCharCode(_ tag: String) -> NSNumber {
        NSNumber(value: tag.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    }

    /// Charge les polices embarquées pour cette session de l'appli.
    /// Dans le .app, macOS les charge déjà via la clé ATSApplicationFontsPath de l'Info.plist ;
    /// cette fonction sert au lancement par `swift run`. On évite `Bundle.module`, qui
    /// plante (fatalError) dans un .app où le bundle de ressources n'est pas à la racine.
    static func registerBundledFonts() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
            Bundle(url: Bundle.main.bundleURL.appendingPathComponent("GoSaver_GoSaver.bundle"))?
                .resourceURL?.appendingPathComponent("Fonts"),
        ]
        guard let folder = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}

extension View {
    /// Toponyme : capitales espacées, comme un nom de région sur une carte.
    func regionStyle() -> some View {
        self.font(Typo.region)
            .textCase(.uppercase)
            .tracking(Typo.regionTracking)
    }
}
