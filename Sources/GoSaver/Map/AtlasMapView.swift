import SwiftUI
import RealityKit
import GoSaverCore

/// La carte 3D dans la fenêtre : on tourne autour à la souris (orbite), on zoome au trackpad.
///
/// Déroulé :
/// - avant le relevé : l'île a déjà sa vraie surface (on connaît l'espace occupé),
///   mais elle est entièrement sous le brouillard ;
/// - pendant : le brouillard s'éclaircit au rythme du relevé ;
/// - à la fin : la vraie géographie est calculée, puis le brouillard se lève.
struct AtlasMapView: View {
    let model: AtlasModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = Entity()
    @State private var scene: AtlasScene?
    @State private var camera = AtlasScene.camera()
    @State private var orbit = Orbit()
    @State private var dragStart: Orbit?
    @State private var zoomStart: Orbit?

    /// Ce qui impose de reconstruire la carte : un nouveau relevé, ou un changement de thème.
    private var buildKey: String { "\(model.phase == .surveyed)-\(colorScheme)" }

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(stage)
            content.add(camera)
            orbit.apply(to: camera)
        }
        .background(Ink.paper)
        // Glisser : tourner autour de la planche. Pincer : se pencher ou s'éloigner.
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = dragStart ?? orbit
                    dragStart = start
                    orbit = start.dragged(by: value.translation)
                    orbit.apply(to: camera)
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomStart ?? orbit
                    zoomStart = start
                    orbit = start.zoomed(by: value.magnification)
                    orbit.apply(to: camera)
                }
                .onEnded { _ in zoomStart = nil }
        )
        .onTapGesture(count: 2) {
            // Double-clic : retour à la vue de départ.
            withAnimation(Motion.survey) { orbit = Orbit() }
            orbit.apply(to: camera)
        }
        .task(id: buildKey) { await rebuild() }
        .onChange(of: model.fogLifted) { _, lifted in
            // Pendant le relevé, le voile s'éclaircit sans disparaître.
            guard model.phase == .surveying else { return }
            scene?.setFog(Float(0.92 - 0.3 * lifted))
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    private func rebuild() async {
        let input = model.atlasInput() ?? model.unsurveyedInput()
        let surveyed = model.phase == .surveyed
        let clock = ContinuousClock()
        var mark = clock.now
        func lap(_ step: String) {
            Log.map.notice("\(step, privacy: .public) : \((clock.now - mark).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
            mark = clock.now
        }
        let layout = await Task.detached(priority: .userInitiated) { AtlasLayout.build(input) }.value
        lap("géographie")

        let print = MapPrint(layout: layout, seaBytes: model.volume.free, side: 3072, unknown: !surveyed)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: print)
        renderer.scale = 1
        let rendered = renderer.cgImage
        lap("impression")
        guard let image = rendered else {
            Log.map.error("impression de la carte impossible")
            return
        }
        let next: AtlasScene
        do {
            next = try await AtlasScene.make(layout: layout, print: image)
        } catch {
            Log.map.error("scène 3D impossible : \(error.localizedDescription, privacy: .public)")
            return
        }
        lap("scène 3D")
        Log.map.notice("carte construite (relevé : \(surveyed))")

        next.setFog(surveyed ? 0.62 : 0.92)
        stage.children.removeAll()
        stage.addChild(next.root)
        scene = next

        if surveyed { await liftFog(from: 0.62, on: next) }
    }

    /// Le brouillard se lève (1,6 s), ou disparaît d'un coup si les animations sont réduites.
    private func liftFog(from start: Float, on scene: AtlasScene) async {
        guard !reduceMotion else { scene.setFog(0); return }
        let duration = 1.6
        let clock = ContinuousClock()
        let begin = clock.now
        while true {
            let t = min((clock.now - begin) / .seconds(duration), 1)
            // Lent au début, comme une brume qui hésite, puis franc.
            let eased = Float(t * t * (3 - 2 * t))
            scene.setFog(start * (1 - eased))
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private var accessibilityDescription: String {
        switch model.phase {
        case .idle: "Carte du disque, sous le brouillard : le relevé n’a pas commencé."
        case .surveying: "Carte du disque, relevé en cours."
        case .surveyed: "Carte du disque. Le détail des terrains est dans le registre."
        }
    }
}

/// Position de la caméra autour de la planche, en coordonnées sphériques.
/// Bornée pour rester lisible : jamais sous la table, jamais à plat sur la carte.
struct Orbit: Equatable {
    /// Rotation autour de la verticale, en radians.
    var yaw: Float = 0
    /// Inclinaison au-dessus de l'horizon, en radians (25° à 80°).
    var pitch: Float = 50 * .pi / 180
    /// Distance au centre, en mètres.
    var distance: Float = 2.5

    static let pitchRange: ClosedRange<Float> = (25 * .pi / 180)...(80 * .pi / 180)
    static let distanceRange: ClosedRange<Float> = 0.7...3.4

    func dragged(by translation: CGSize) -> Orbit {
        var next = self
        next.yaw -= Float(translation.width) * 0.006
        next.pitch = (pitch + Float(translation.height) * 0.004).clamped(to: Self.pitchRange)
        return next
    }

    func zoomed(by magnification: CGFloat) -> Orbit {
        var next = self
        next.distance = (distance / Float(magnification)).clamped(to: Self.distanceRange)
        return next
    }

    @MainActor func apply(to camera: Entity) {
        let target = SIMD3<Float>(0, 0.02, 0.2)
        let eye = target + distance * SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        camera.look(at: target, from: eye, relativeTo: nil)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
