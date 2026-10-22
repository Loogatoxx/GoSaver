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

        // Impression de la carte seule (2D), pour vérifier la cartographie.
        if let input = model.atlasInput() {
            let clock = ContinuousClock()
            let start = clock.now
            let layout = AtlasLayout.build(input)
            let laidOut = clock.now
            for (scheme, name) in [(ColorScheme.light, "papier"), (.dark, "lampe")] {
                NSAppearance.current = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                let print = MapPrint(layout: layout, seaBytes: model.volume.free, side: 2048)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: print)
                renderer.scale = 1
                guard let cg = renderer.cgImage else { continue }
                writePNG(cg, to: folder.appendingPathComponent("carte-\(name).png"))
                // Le plan-relief 3D, rendu hors écran.
                let scene = waitFor { try await AtlasScene.make(layout: layout, print: cg) }
                scene?.setFog(0)
                if let scene, let image = try? SceneRenderer.render(scene.root, camera: AtlasScene.camera(), width: 1600, height: 1000) {
                    writePNG(image, to: folder.appendingPathComponent("relief-\(name).png"))
                }
            }
            print("géographie \(laidOut - start), impressions \(clock.now - laidOut)")
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

    /// Attend une tâche asynchrone en faisant tourner la boucle principale (mode instantané seulement).
    static func waitFor<T>(_ work: @escaping @MainActor () async throws -> T) -> T? {
        var result: T?
        var done = false
        Task { @MainActor in
            result = try? await work()
            done = true
        }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return result
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
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
