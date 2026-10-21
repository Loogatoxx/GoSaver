import SwiftUI
import GoSaverCore

/// Motif cartographique d'un terrain (docs/DESIGN_SYSTEM.md §3.3).
/// Les terrains se distinguent par le motif, pas par la couleur : lisible
/// pour les daltoniens, et fidèle aux cartes imprimées en deux encres.
struct TerrainSwatch: View {
    let terrain: Terrain

    var body: some View {
        Canvas { context, size in
            TerrainPattern.draw(terrain, in: CGRect(origin: .zero, size: size), context: &context)
            context.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(Ink.ink), lineWidth: Stroke.hairline)
        }
        .accessibilityHidden(true)
    }
}

enum TerrainPattern {
    static func ink(for terrain: Terrain) -> Color {
        switch terrain {
        case .massif, .city: Ink.ink
        case .marsh, .delta: Ink.sea
        case .fields, .quarry: Ink.contour
        case .forest: Ink.forest
        case .ruins: Ink.vermilion
        case .shore: Ink.inkFaded
        }
    }

    /// Dessine le motif d'un terrain dans `rect`, découpé à ses bords.
    static func draw(_ terrain: Terrain, in rect: CGRect, context: inout GraphicsContext) {
        let color = ink(for: terrain)
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            var path = Path()
            switch terrain {
            case .massif:
                // Hachures de pente serrées, à 60°.
                for x in stride(from: rect.minX - rect.height, through: rect.maxX, by: 2.5) {
                    path.move(to: CGPoint(x: x, y: rect.maxY))
                    path.addLine(to: CGPoint(x: x + rect.height * 0.58, y: rect.minY))
                }
                layer.stroke(path, with: .color(color), lineWidth: 0.7)

            case .city:
                // Îlots bâtis pleins, rues laissées en réserve.
                let block: CGFloat = 4, street: CGFloat = 1.6
                var y = rect.minY + 1
                var row = 0
                while y < rect.maxY {
                    var x = rect.minX + 1 + (row.isMultiple(of: 2) ? 0 : 2)
                    while x < rect.maxX {
                        path.addRect(CGRect(x: x, y: y, width: block, height: block * 0.8))
                        x += block + street
                    }
                    y += block * 0.8 + street
                    row += 1
                }
                layer.fill(path, with: .color(color))

            case .marsh:
                // Tirets horizontaux courts, en quinconce.
                var row = 0
                for y in stride(from: rect.minY + 2, through: rect.maxY, by: 3) {
                    let offset: CGFloat = row.isMultiple(of: 2) ? 0 : 3
                    for x in stride(from: rect.minX + offset, through: rect.maxX, by: 6) {
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x + 3, y: y))
                    }
                    row += 1
                }
                layer.stroke(path, with: .color(color), lineWidth: 0.8)

            case .delta:
                // Bras d'eau qui se ramifient de gauche à droite.
                let midY = rect.midY
                for branch in [-0.32, 0.0, 0.32] {
                    path.move(to: CGPoint(x: rect.minX, y: midY))
                    path.addCurve(to: CGPoint(x: rect.maxX, y: midY + rect.height * branch * 1.4),
                                  control1: CGPoint(x: rect.midX, y: midY),
                                  control2: CGPoint(x: rect.midX, y: midY + rect.height * branch))
                }
                layer.stroke(path, with: .color(color), lineWidth: 0.9)

            case .fields:
                // Sillons parallèles, deux parcelles d'orientation différente.
                let split = rect.midX
                for y in stride(from: rect.minY + 1, through: rect.maxY, by: 2.2) {
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: split - 0.8, y: y))
                }
                for x in stride(from: split + 0.8, through: rect.maxX, by: 2.2) {
                    path.move(to: CGPoint(x: x, y: rect.minY))
                    path.addLine(to: CGPoint(x: x, y: rect.maxY))
                }
                layer.stroke(path, with: .color(color), lineWidth: 0.6)

            case .forest:
                // Semis d'arbres : petits cercles ouverts posés en quinconce.
                var row = 0
                for y in stride(from: rect.minY + 3, through: rect.maxY, by: 4.5) {
                    let offset: CGFloat = row.isMultiple(of: 2) ? 2 : 4.5
                    for x in stride(from: rect.minX + offset, through: rect.maxX, by: 5) {
                        path.addEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
                    }
                    row += 1
                }
                layer.stroke(path, with: .color(color), lineWidth: 0.7)

            case .quarry:
                // Déblais : petits triangles irréguliers (motif déterministe).
                var seed: UInt64 = 0x9E3779B97F4A7C15
                func next() -> CGFloat {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                }
                for y in stride(from: rect.minY + 2, through: rect.maxY, by: 4) {
                    for x in stride(from: rect.minX + 1, through: rect.maxX, by: 4) {
                        let px = x + next() * 1.5, py = y + next() * 1.5, s = 1.4 + next()
                        path.move(to: CGPoint(x: px, y: py + s))
                        path.addLine(to: CGPoint(x: px + s, y: py + s))
                        path.addLine(to: CGPoint(x: px + s * 0.4, y: py))
                        path.closeSubpath()
                    }
                }
                layer.stroke(path, with: .color(color), lineWidth: 0.6)

            case .ruins:
                // Murs interrompus et croix.
                for y in stride(from: rect.minY + 3, through: rect.maxY, by: 6) {
                    for x in stride(from: rect.minX + 1, through: rect.maxX, by: 7) {
                        path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + 2.5, y: y))
                        path.move(to: CGPoint(x: x + 4, y: y - 1.5)); path.addLine(to: CGPoint(x: x + 5.5, y: y + 1.5))
                        path.move(to: CGPoint(x: x + 5.5, y: y - 1.5)); path.addLine(to: CGPoint(x: x + 4, y: y + 1.5))
                    }
                }
                layer.stroke(path, with: .color(color), lineWidth: 0.8)

            case .shore:
                // Grève : pointillé de galets.
                for y in stride(from: rect.minY + 1.5, through: rect.maxY, by: 3) {
                    for x in stride(from: rect.minX + 1.5, through: rect.maxX, by: 3) {
                        path.addEllipse(in: CGRect(x: x, y: y, width: 0.9, height: 0.9))
                    }
                }
                layer.fill(path, with: .color(color))
            }
        }
    }
}
