import SwiftUI
import AppKit
import GoSaverCore

/// Mode développeur : `GoSaver --snapshot <dossier> [--survey]` dessine l'écran principal
/// en clair et en sombre dans des PNG, puis quitte. Avec `--survey`, un vrai relevé
/// (lecture seule) est fait d'abord. Sert à vérifier le rendu sans capture d'écran.
@MainActor
enum Snapshot {
    /// Vrai pendant le rendu d'un instantané.
    static var isActive = CommandLine.arguments.contains("--snapshot")

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) else { return }
        let folder = URL(fileURLWithPath: args[flag + 1])
        Typo.registerBundledFonts()

        let model = AtlasModel()
        if args.contains("--survey") {
            model.load(blockingSurvey())
        }

        for (scheme, name) in [(ColorScheme.light, "papier"), (.dark, "lampe")] {
            NSAppearance.current = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let view = RootView(model: model)
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

    /// Attend un relevé complet. Le relevé tourne hors du fil principal,
    /// on peut donc bloquer celui-ci sans interblocage (uniquement en mode instantané).
    private static func blockingSurvey() -> Survey {
        nonisolated(unsafe) var result: Survey?
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            result = await Surveyor().surveyAll()
            done.signal()
        }
        done.wait()
        return result!
    }
}
