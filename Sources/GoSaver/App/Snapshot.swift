import SwiftUI
import AppKit

/// Mode développeur : `GoSaver --snapshot <dossier>` dessine l'écran principal
/// en clair et en sombre dans des PNG, puis quitte. Sert à vérifier le rendu
/// sans capture d'écran (qui demanderait une permission système).
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) else { return }
        let folder = URL(fileURLWithPath: args[flag + 1])
        Typo.registerBundledFonts()

        for (scheme, name) in [(ColorScheme.light, "papier"), (.dark, "lampe")] {
            NSAppearance.current = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let view = RootView()
                .frame(width: 1280, height: 800)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: folder.appendingPathComponent("gosaver-\(name).png"))
        }
        exit(0)
    }
}
