import SwiftUI
import GoSaverCore

/// L'impression de la carte : ce qui est gravé sur le papier, avant d'être drapé
/// sur le relief 3D. Dessinée avec les mêmes motifs que le Registre (TerrainPattern),
/// pour que la légende et la carte parlent exactement la même langue.
///
/// Calques, du fond vers le dessus :
/// papier → mer et lignes d'eau → motifs de terrain → courbes de niveau →
/// frontières → côte → noms de lieux.
struct MapPrint: View {
    let layout: AtlasLayout
    let seaBytes: Int64
    /// Taille de l'impression en points (= pixels avec une échelle de rendu de 1).
    let side: CGFloat
    /// Terre encore inconnue (avant le relevé) : on ne grave que la côte et la mer.
    var unknown = false

    /// Les motifs sont dessinés pour une lecture à l'écran ; sur une texture de
    /// plusieurs milliers de pixels, on les agrandit d'autant.
    private var patternScale: CGFloat { side / 900 }
    private var cell: CGFloat { side / CGFloat(layout.size) }

    var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size)
            context.fill(Path(frame), with: .color(Ink.paperRaised))
            drawSea(&context, frame)
            if !unknown {
                drawTerrains(&context, frame)
                drawContours(&context)
                drawBorders(&context)
            }
            drawCoast(&context)
            if !unknown { drawLabels(&context) }
            drawGrain(&context, frame)
        }
        .frame(width: side, height: side)
    }

    // MARK: - Calques

    private func drawSea(_ context: inout GraphicsContext, _ frame: CGRect) {
        // Au-delà de la limite du disque : papier hors carte, légèrement grisé à l'encre.
        context.fill(Path(frame), with: .color(Ink.paperSunken))
        let limit = layout.diskLimit
        let insideLimit = indicator { layout.land.values[$0] || layout.seaDistance.values[$0] <= limit }
        if let mask = MaskImage.make(field: insideLimit, resolution: 768) {
            context.drawLayer { layer in
                layer.clipToLayer { $0.draw(Image(decorative: mask, scale: 1).interpolation(.high), in: frame) }
                layer.fill(Path(frame), with: .color(Ink.seaWash))
                // Lignes d'eau parallèles à la côte, de plus en plus espacées vers le large :
                // la convention des cartes gravées du XIXᵉ siècle.
                var distance: Float = 1.2, index = 0
                while distance < limit - 0.8 {
                    let path = segmentsPath(isoSegments(layout.seaDistance, level: distance))
                    layer.stroke(path, with: .color(Ink.sea.opacity(0.75 - Double(index) * 0.08)),
                                 lineWidth: max(1, cell * 0.09))
                    distance += 1.3 + Float(index) * 0.6
                    index += 1
                }
            }
        }
        // La limite elle-même : tireté d'encre bleue, comme une limite d'eaux territoriales.
        context.stroke(segmentsPath(isoSegments(insideLimit, level: 0.5)),
                       with: .color(Ink.sea),
                       style: StrokeStyle(lineWidth: max(1.5, cell * 0.14), dash: [cell * 0.8, cell * 0.45]))
    }

    private func drawTerrains(_ context: inout GraphicsContext, _ frame: CGRect) {
        for region in layout.regions {
            let index = Int8(Terrain.allCases.firstIndex(of: region.terrain)!)
            guard let mask = MaskImage.make(layout: layout, resolution: 768, where: { layout.terrain.values[$0] == index })
            else { continue }
            context.drawLayer { layer in
                layer.clipToLayer { clip in
                    clip.draw(Image(decorative: mask, scale: 1).interpolation(.high), in: frame)
                }
                layer.fill(Path(frame), with: .color(Ink.paperRaised))
                // Motif atténué : présent mais sans écraser les courbes de niveau ni les noms.
                layer.opacity = Self.patternOpacity(region.terrain)
                layer.scaleBy(x: patternScale, y: patternScale)
                TerrainPattern.draw(region.terrain, in: CGRect(x: 0, y: 0, width: side / patternScale, height: side / patternScale),
                                    context: &layer)
            }
        }
    }

    static func patternOpacity(_ terrain: Terrain) -> Double {
        switch terrain {
        case .city: 0.28        // îlots pleins : très couvrant
        case .massif: 0.4
        case .forest, .ruins: 0.6
        default: 0.5
        }
    }

    private func drawContours(_ context: inout GraphicsContext) {
        // Une courbe tous les 6 % d'altitude, une courbe maîtresse toutes les cinq.
        let fine = upsampled(layout.height, factor: 2)
        for step in 1...16 {
            let level = Float(step) * 0.06
            let segments = isoSegments(fine, level: level)
            guard !segments.isEmpty else { continue }
            let master = step % 5 == 0
            context.stroke(segmentsPath(segments, scale: cell / 2),
                           with: .color(Ink.contour.opacity(master ? 1 : 0.8)),
                           lineWidth: max(1.2, cell * (master ? 0.2 : 0.11)))
        }
    }

    private func drawBorders(_ context: inout GraphicsContext) {
        // Limites de lieux : pointillé fin.
        for index in layout.places.indices {
            let field = indicator { layout.place.values[$0] == Int32(index) }
            context.stroke(segmentsPath(isoSegments(field, level: 0.5)),
                           with: .color(Ink.ink.opacity(0.35)),
                           style: StrokeStyle(lineWidth: max(1, cell * 0.07), dash: [cell * 0.35, cell * 0.3]))
        }
        // Limites de terrains : trait-point, comme une frontière administrative.
        for region in layout.regions {
            let index = Int8(Terrain.allCases.firstIndex(of: region.terrain)!)
            let field = indicator { layout.terrain.values[$0] == index }
            context.stroke(segmentsPath(isoSegments(field, level: 0.5)),
                           with: .color(Ink.ink.opacity(0.75)),
                           style: StrokeStyle(lineWidth: max(1.5, cell * 0.14), dash: [cell * 0.9, cell * 0.3, cell * 0.15, cell * 0.3]))
        }
    }

    private func drawCoast(_ context: inout GraphicsContext) {
        let field = indicator { layout.land.values[$0] }
        let path = segmentsPath(isoSegments(field, level: 0.5))
        context.stroke(path, with: .color(Ink.ink), lineWidth: max(2, cell * 0.22))
    }

    private func drawLabels(_ context: inout GraphicsContext) {
        var taken: [CGRect] = []
        let inner = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: cell * 2, dy: cell * 2)

        /// Pose un nom s'il tient dans le cadre et ne chevauche aucun autre.
        /// `make` fabrique le texte dans une couleur donnée (encre ou halo).
        @discardableResult
        func place(at point: CGPoint, halo: Bool = true, _ make: (Color, Color) -> Text) -> Bool {
            let resolved = context.resolve(make(Ink.ink, Ink.inkFaded))
            let size = resolved.measure(in: CGSize(width: side, height: side))
            var rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                              width: size.width, height: size.height)
            // Glisse le nom à l'intérieur du cadre plutôt que de le couper.
            rect.origin.x = min(max(rect.minX, inner.minX), inner.maxX - rect.width)
            rect.origin.y = min(max(rect.minY, inner.minY), inner.maxY - rect.height)
            let footprint = rect.insetBy(dx: -cell * 0.5, dy: -cell * 0.25)
            guard rect.width < inner.width, !taken.contains(where: { $0.intersects(footprint) }) else { return false }
            taken.append(footprint)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            if halo {
                // Halo papier : le nom reste lisible par-dessus les hachures, comme sur une carte imprimée.
                let haloText = context.resolve(make(Ink.paperRaised, Ink.paperRaised))
                let r = max(1.5, cell * 0.1)
                for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 6) {
                    context.draw(haloText, at: CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle)))
                }
            }
            context.draw(resolved, at: center)
            return true
        }
        let unit = side / 900

        // Terrains d'abord : grandes capitales espacées.
        for region in layout.regions.filter({ $0.cellCount > 0 }).sorted(by: { $0.cellCount > $1.cellCount }) {
            let size = min(26, max(11, sqrt(Double(region.cellCount)) * 0.45)) * unit
            place(at: point(region.label, nudge: -size * 0.9)) { ink, _ in
                Text(region.terrain.name.uppercased())
                    .font(.custom("Archivo", size: size).weight(.semibold))
                    .tracking(size * 0.32)
                    .foregroundColor(ink)
            }
        }
        // Puis les lieux nommés, du plus gros au plus petit ; on saute ceux qui chevauchent.
        for item in layout.places.filter({ !$0.isOthers && $0.cellCount > 0 }).sorted(by: { $0.bytes > $1.bytes }) {
            let size = min(15, max(8.5, sqrt(Double(item.cellCount)) * 0.4)) * unit
            place(at: point(item.label, nudge: size * 0.6)) { ink, faded in
                let name = Text(item.name).font(.custom("Archivo", size: size).weight(.medium)).foregroundColor(ink)
                let figure = Text("  " + Bytes.format(item.bytes))
                    .font(.custom("IBM Plex Mono", size: size * 0.82)).foregroundColor(faded)
                return Text("\(name)\(figure)")
            }
        }
        // La mer : en italique, convention hydrographique — seulement s'il y a la place.
        if let sea = seaLabelPoint() {
            let size = 14 * unit
            place(at: sea, halo: false) { _, _ in
                Text("Mer libre — \(Bytes.format(seaBytes))")
                    .font(.custom("Newsreader", size: size).italic())
                    .foregroundColor(Ink.sea)
            }
        }
    }

    private func drawGrain(_ context: inout GraphicsContext, _ frame: CGRect) {
        // Grain du papier : fines piqûres déterministes, très légères.
        var generator = SeededGenerator(seed: 42)
        var dots = Path()
        let r = max(0.6, side / 3000)
        for _ in 0..<Int(side * 6) {
            let x = CGFloat(Double(generator.next() % 100_000) / 100_000) * frame.width
            let y = CGFloat(Double(generator.next() % 100_000) / 100_000) * frame.height
            dots.addEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
        context.fill(dots, with: .color(Ink.ink.opacity(0.07)))
    }

    // MARK: - Outils

    private func point(_ normalized: SIMD2<Double>, nudge: CGFloat = 0) -> CGPoint {
        CGPoint(x: normalized.x * side, y: normalized.y * side + nudge)
    }

    /// Point de la mer le plus éloigné de la côte, dans le cadre.
    private func seaLabelPoint() -> CGPoint? {
        let n = layout.size
        var best: (Int, Float)?
        for y in 2..<(n - 2) {
            for x in 2..<(n - 2) where !layout.land[x, y] {
                // Au milieu de la bande de mer libre, là où elle est la plus large.
                let d = layout.seaDistance[x, y]
                guard abs(d - layout.diskLimit / 2) < 0.6 else { continue }
                let width = layout.diskLimit
                if width > (best?.1 ?? 0) { best = (y * n + x, width) }
            }
        }
        guard let (index, width) = best, width > 4 else { return nil }
        return CGPoint(x: (CGFloat(index % n) + 0.5) * cell, y: (CGFloat(index / n) + 0.5) * cell)
    }

    /// Champ 0/1 adouci, dont l'isoligne 0,5 donne une frontière arrondie.
    private func indicator(_ predicate: (Int) -> Bool) -> Raster<Float> {
        var field = Raster<Float>(size: layout.size, repeating: 0)
        for i in field.values.indices where predicate(i) { field.values[i] = 1 }
        return field.smoothed(passes: 2)
    }

    private func upsampled(_ field: Raster<Float>, factor: Int) -> Raster<Float> {
        var out = Raster<Float>(size: field.size * factor, repeating: 0)
        for y in 0..<out.size {
            for x in 0..<out.size {
                let sx: Double = (Double(x) + 0.5) / Double(factor) - 0.5
                let sy: Double = (Double(y) + 0.5) / Double(factor) - 0.5
                out[x, y] = field.sample(sx, sy)
            }
        }
        return out
    }

    /// Chemin à partir de segments en coordonnées de grille (centre des cellules).
    private func segmentsPath(_ segments: [(SIMD2<Double>, SIMD2<Double>)], scale: CGFloat? = nil) -> Path {
        let s = scale ?? cell
        var path = Path()
        for (a, b) in segments {
            path.move(to: CGPoint(x: (a.x + 0.5) * s, y: (a.y + 0.5) * s))
            path.addLine(to: CGPoint(x: (b.x + 0.5) * s, y: (b.y + 0.5) * s))
        }
        return path
    }
}

/// Masque alpha lissé d'une zone de la grille, pour découper les motifs.
enum MaskImage {
    static func make(layout: AtlasLayout, resolution: Int, where predicate: (Int) -> Bool) -> CGImage? {
        var field = Raster<Float>(size: layout.size, repeating: 0)
        for i in field.values.indices where predicate(i) { field.values[i] = 1 }
        return make(field: field.smoothed(passes: 2), resolution: resolution)
    }

    /// Masque à partir d'un champ déjà adouci (seuil à 0,5).
    static func make(field: Raster<Float>, resolution: Int) -> CGImage? {
        let ratio = Double(field.size) / Double(resolution)
        var pixels = [UInt8](repeating: 0, count: resolution * resolution * 4)
        for y in 0..<resolution {
            for x in 0..<resolution {
                let v = field.sample((Double(x) + 0.5) * ratio - 0.5, (Double(y) + 0.5) * ratio - 0.5)
                // Seuil adouci autour de 0,5 : bord net mais sans escalier.
                let t = min(max((v - 0.42) / 0.16, 0), 1)
                let alpha = UInt8(t * t * (3 - 2 * t) * 255)
                pixels[(y * resolution + x) * 4 + 3] = alpha
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: resolution, height: resolution, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: resolution * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
