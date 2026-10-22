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

        // `--icone` : l'icône seule, en 1024 × 1024.
        if args.contains("--icone") {
            let renderer = ImageRenderer(content: IconArt().frame(width: 1024, height: 1024))
            renderer.scale = 1
            if let image = renderer.cgImage { writePNG(image, to: folder.appendingPathComponent("icone-1024.png")) }
            exit(0)
        }

        let model = AtlasModel()
        if args.contains("--survey") {
            let survey = blockingSurvey()
            _ = waitFor { await model.load(survey) }
            // `--ruine` : ouvre la fiche d'expertise de la première ruine.
            if args.contains("--ruine") { model.selectedID = model.visibleRuins.first?.id }
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
                // Contrôle de la visée : jalon planté sur le plus gros lieu, et croix là où
                // notre propre calcul de projection dit qu'il doit apparaître.
                let size = CGSize(width: 1600, height: 1000)
                let orbit = Orbit()
                let camera = AtlasScene.camera()
                orbit.apply(to: camera)
                var cross: CGPoint?
                if let biggest = layout.places.filter({ !$0.isOthers }).max(by: { $0.bytes < $1.bytes }) {
                    let ground = AtlasScene.geometry.world(normalized: biggest.label, on: layout)
                    scene?.plant(at: ground, animated: false)
                    cross = orbit.project(ground, in: size)
                }
                if let scene, var image = try? SceneRenderer.render(scene.root, camera: camera, width: Int(size.width), height: Int(size.height)) {
                    if let cross { image = drawCross(on: image, at: cross) ?? image }
                    writePNG(image, to: folder.appendingPathComponent("relief-\(name).png"))
                }
            }
            print("géographie \(laidOut - start), impressions \(clock.now - laidOut)")
        }

        // `--assechement` : feuille de confirmation sur le vrai plan (lecture seule, rien n'est supprimé).
        if args.contains("--assechement") {
            model.previewDrain(Drainer.standard().plan())
        }
        // `--acces` : feuille d'accès complet au disque.
        if args.contains("--acces") {
            model.accessSheetOpen = true
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

    /// Trace une petite croix vermillon (contrôle visuel de la visée).
    static func drawCross(on image: CGImage, at point: CGPoint) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let y = CGFloat(image.height) - point.y
        context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(2)
        context.move(to: CGPoint(x: point.x - 14, y: y)); context.addLine(to: CGPoint(x: point.x + 14, y: y))
        context.move(to: CGPoint(x: point.x, y: y - 14)); context.addLine(to: CGPoint(x: point.x, y: y + 14))
        context.strokePath()
        return context.makeImage()
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
