import SwiftUI
import RealityKit
import GoSaverCore

/// La carte 3D dans la fenêtre.
///
/// Déroulé :
/// - avant le relevé : l'île a déjà sa vraie surface (on connaît l'espace occupé),
///   mais elle est entièrement sous le brouillard ;
/// - pendant : le brouillard s'éclaircit au rythme du relevé ;
/// - à la fin : la vraie géographie est calculée, puis le brouillard se lève.
///
/// Gestes : glisser pour tourner, pincer pour zoomer, survoler pour lire un lieu,
/// cliquer pour le sélectionner (la caméra s'y rend), double-clic pour revenir.
struct AtlasMapView: View {
    let model: AtlasModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = Entity()
    @State private var scene: AtlasScene?
    @State private var layout: AtlasLayout?
    @State private var camera = AtlasScene.camera()
    @State private var orbit = Orbit()
    @State private var dragStart: Orbit?
    @State private var zoomStart: Orbit?
    @State private var flight: Task<Void, Never>?
    @State private var viewSize: CGSize = .zero
    @State private var hoverPoint: CGPoint?
    @State private var lastClick: Date?
    /// Révision du terrain actuellement affichée (pour savoir si c'est une érosion).
    @State private var shownRevision = 0

    /// Ce qui impose de reconstruire la carte : un nouveau relevé, ou un changement de thème.
    private var buildKey: String { "\(model.phase == .surveyed)-\(colorScheme)-\(model.landRevision)" }

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(stage)
            content.add(camera)
            orbit.apply(to: camera)
        }
        .background(Ink.paper)
        // La vue RealityKit est une vue AppKit qui garde les clics pour elle : on pose
        // par-dessus un calque SwiftUI transparent qui reçoit tous les gestes.
        .overlay {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            flight?.cancel()
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
                            flight?.cancel()
                            let start = zoomStart ?? orbit
                            zoomStart = start
                            orbit = start.zoomed(by: value.magnification)
                            orbit.apply(to: camera)
                        }
                        .onEnded { _ in zoomStart = nil }
                )
                // Un seul geste de clic : le nombre de clics décide (double-clic = vue de départ).
                // Deux gestes concurrents (simple + double) se bloquaient mutuellement.
                .simultaneousGesture(
                    SpatialTapGesture(count: 1, coordinateSpace: .local)
                        .onEnded { value in handleClick(at: value.location) }
                )
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let point):
                        hoverPoint = point
                        let place = pick(point)
                        model.hoveredID = place?.isOthers == false ? place?.id : nil
                    case .ended:
                        hoverPoint = nil
                        model.hoveredID = nil
                    }
                }
        }
        .overlay(alignment: .topLeading) { hoverLabel }
        .task(id: buildKey) { await rebuild() }
        .onChange(of: model.fogLifted) { _, lifted in
            // Pendant le relevé, le voile s'éclaircit sans disparaître.
            guard model.phase == .surveying else { return }
            scene?.setFog(Float(0.92 - 0.3 * lifted))
        }
        .onChange(of: model.selectedID) { _, id in focus(on: id) }
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Construction

    private func rebuild() async {
        let input = model.atlasInput() ?? model.unsurveyedInput()
        let surveyed = model.phase == .surveyed
        let clock = ContinuousClock()
        var mark = clock.now
        func lap(_ step: String) {
            Log.map.notice("\(step, privacy: .public) : \((clock.now - mark).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
            mark = clock.now
        }
        let built = await Task.detached(priority: .userInitiated) { AtlasLayout.build(input) }.value
        lap("géographie")

        let print = MapPrint(layout: built, seaBytes: model.volume.free, side: 3072, unknown: !surveyed)
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
            next = try await AtlasScene.make(layout: built, print: image)
        } catch {
            Log.map.error("scène 3D impossible : \(error.localizedDescription, privacy: .public)")
            return
        }
        lap("scène 3D")
        Log.map.notice("carte construite (relevé : \(surveyed))")

        // Érosion : le terrain a changé après un assèchement. Pas de brouillard,
        // l'ancien relief s'affaisse puis le nouveau se pose.
        let erosion = surveyed && scene != nil && model.landRevision != shownRevision
        shownRevision = model.landRevision
        if erosion, let old = scene, !reduceMotion {
            await animate(duration: 0.6) { t in
                old.relief.scale.y = 1 - 0.35 * Float(t * t)
            }
        }

        next.setFog(surveyed ? (erosion ? 0 : 0.62) : 0.92)
        stage.children.removeAll()
        stage.addChild(next.root)
        scene = next
        layout = surveyed ? built : nil

        if erosion, !reduceMotion {
            await animate(duration: 0.8) { t in
                // Le nouveau terrain se pose, avec un léger tassement final.
                let settle = 1 - pow(1 - t, 3)
                next.relief.scale.y = 0.65 + 0.35 * Float(settle) + 0.03 * Float(sin(t * .pi))
            }
            next.relief.scale.y = 1
        } else if surveyed, !erosion {
            await liftFog(from: 0.62, on: next)
        }
    }

    /// Le brouillard se lève (1,6 s), ou disparaît d'un coup si les animations sont réduites.
    private func liftFog(from start: Float, on scene: AtlasScene) async {
        guard !reduceMotion else { scene.setFog(0); return }
        await animate(duration: 1.6) { t in
            // Lent au début, comme une brume qui hésite, puis franc.
            scene.setFog(start * (1 - Float(t * t * (3 - 2 * t))))
        }
    }

    // MARK: - Visée et sélection

    /// Clic simple : sélectionne le lieu visé. Double-clic (détecté par l'horodatage) : vue de départ.
    private func handleClick(at location: CGPoint) {
        let now = Date()
        defer { lastClick = now }
        if let last = lastClick, now.timeIntervalSince(last) < NSEvent.doubleClickInterval {
            model.selectedID = nil
            fly(to: Orbit())
            return
        }
        let picked = pick(location)
        Log.map.notice("clic \(Int(location.x)),\(Int(location.y)) → \(picked?.name ?? "rien", privacy: .public)")
        if let place = picked, !place.isOthers {
            model.toggleSelection(place.id)
        } else {
            model.selectedID = nil
        }
    }

    /// Lieu sous un point de la vue : rayon depuis la caméra jusqu'au relief.
    private func pick(_ point: CGPoint) -> AtlasLayout.LaidPlace? {
        guard let layout, let (eye, direction) = orbit.ray(through: point, in: viewSize),
              let cell = AtlasScene.geometry.hit(origin: eye, direction: direction, layout: layout) else { return nil }
        return layout.place(at: cell)
    }

    /// Plante le jalon sur le lieu choisi et y emmène la caméra ; sans sélection, retour à la vue d'ensemble.
    private func focus(on id: String?) {
        guard let layout, let id, let place = layout.places.first(where: { $0.id == id }) else {
            scene?.plant(at: nil, animated: false)
            if id == nil { fly(to: Orbit(yaw: orbit.yaw, pitch: orbit.pitch)) }
            return
        }
        let ground = AtlasScene.geometry.world(normalized: place.label, on: layout)
        scene?.plant(at: ground, animated: !reduceMotion)
        var destination = orbit
        destination.focus = ground
        destination.distance = min(orbit.distance, 1.45)
        fly(to: destination)
    }

    /// Vol de caméra en douceur vers une nouvelle position (0,9 s).
    private func fly(to destination: Orbit) {
        flight?.cancel()
        guard !reduceMotion else {
            orbit = destination
            orbit.apply(to: camera)
            return
        }
        let start = orbit
        flight = Task {
            await animate(duration: 0.9) { t in
                let eased = Float(1 - pow(1 - t, 3))
                orbit = start.interpolated(to: destination, by: eased)
                orbit.apply(to: camera)
            }
        }
    }

    /// Petite boucle d'animation à ~60 images/s, interrompue si la tâche est annulée.
    private func animate(duration: Double, _ step: (Double) -> Void) async {
        let clock = ContinuousClock()
        let begin = clock.now
        while !Task.isCancelled {
            let t = min((clock.now - begin) / .seconds(duration), 1)
            step(t)
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    // MARK: - Étiquette de survol

    @ViewBuilder
    private var hoverLabel: some View {
        if let point = hoverPoint, let id = model.hoveredID, let landmark = model.landmark(id: id) {
            VStack(alignment: .leading, spacing: 2) {
                Text(landmark.title).font(Typo.bodyStrong).foregroundStyle(Ink.ink)
                HStack(spacing: Space.s2) {
                    Text(landmark.terrain.name).font(Typo.label).foregroundStyle(Ink.inkFaded)
                    Text(Bytes.format(landmark.bytes)).font(Typo.figure).foregroundStyle(Ink.ink)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(Ink.paperRaised.sheetShadow())
            .overlay(Rectangle().strokeBorder(Ink.ink, lineWidth: Stroke.hairline))
            .fixedSize()
            .offset(x: min(point.x + 16, max(0, viewSize.width - 220)), y: point.y + 18)
            .allowsHitTesting(false)
            .transition(.opacity)
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

/// Position de la caméra autour d'un point de la planche, en coordonnées sphériques.
/// Bornée pour rester lisible : jamais sous la table, jamais à plat sur la carte.
struct Orbit: Equatable {
    /// Rotation autour de la verticale, en radians.
    var yaw: Float = 0
    /// Inclinaison au-dessus de l'horizon, en radians (25° à 80°).
    var pitch: Float = 50 * .pi / 180
    /// Distance au point visé, en mètres.
    var distance: Float = 2.5
    /// Point visé : le centre de la planche, ou le lieu sélectionné.
    var focus: SIMD3<Float> = [0, 0.02, 0.2]

    static let pitchRange: ClosedRange<Float> = (25 * .pi / 180)...(80 * .pi / 180)
    static let distanceRange: ClosedRange<Float> = 0.5...3.4

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

    func interpolated(to other: Orbit, by t: Float) -> Orbit {
        Orbit(yaw: yaw + (other.yaw - yaw) * t,
              pitch: pitch + (other.pitch - pitch) * t,
              distance: distance + (other.distance - distance) * t,
              focus: focus + (other.focus - focus) * t)
    }

    func eyeAndTarget() -> (SIMD3<Float>, SIMD3<Float>) {
        let eye = focus + distance * SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        return (eye, focus)
    }

    /// Repère de la caméra : axes avant, droite et haut.
    private func basis() -> (eye: SIMD3<Float>, forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>) {
        let (eye, target) = eyeAndTarget()
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
        return (eye, forward, right, simd_cross(right, forward))
    }

    /// Rayon partant de l'œil et passant par un point de la vue (champ de vision vertical).
    func ray(through point: CGPoint, in size: CGSize) -> (SIMD3<Float>, SIMD3<Float>)? {
        guard size.width > 0, size.height > 0 else { return nil }
        let (eye, forward, right, up) = basis()
        let tanHalf = tan(AtlasScene.fieldOfView * .pi / 360)
        let aspect = Float(size.width / size.height)
        let nx = Float(2 * point.x / size.width - 1)
        let ny = Float(1 - 2 * point.y / size.height)
        return (eye, forward + right * (nx * tanHalf * aspect) + up * (ny * tanHalf))
    }

    /// Opération inverse : où un point 3D apparaît dans la vue.
    func project(_ point: SIMD3<Float>, in size: CGSize) -> CGPoint {
        let (eye, forward, right, up) = basis()
        let v = point - eye
        let depth = simd_dot(v, forward)
        let tanHalf = tan(AtlasScene.fieldOfView * .pi / 360)
        let aspect = Float(size.width / size.height)
        let nx = simd_dot(v, right) / depth / (tanHalf * aspect)
        let ny = simd_dot(v, up) / depth / tanHalf
        return CGPoint(x: CGFloat((nx + 1) / 2) * size.width, y: CGFloat((1 - ny) / 2) * size.height)
    }

    @MainActor func apply(to camera: Entity) {
        let (eye, target) = eyeAndTarget()
        camera.look(at: target, from: eye, relativeTo: nil)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
