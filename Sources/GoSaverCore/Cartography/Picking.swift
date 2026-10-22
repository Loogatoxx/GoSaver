import Foundation
import simd

/// Passage entre la planche 3D (mètres) et la grille de la géographie (cellules).
///
/// La planche est un carré de côté `boardSize`, centré sur l'origine, posé sur le plan
/// horizontal (x vers la droite, z vers le spectateur, y vers le haut). Le relief monte
/// jusqu'à `reliefHeight` au plus haut sommet.
public struct BoardGeometry: Sendable {
    public let boardSize: Float
    public let reliefHeight: Float

    public init(boardSize: Float, reliefHeight: Float) {
        self.boardSize = boardSize
        self.reliefHeight = reliefHeight
    }

    /// Point de la planche (x, z) → coordonnées continues de la grille.
    public func grid(x: Float, z: Float, size: Int) -> SIMD2<Double> {
        SIMD2(Double((x / boardSize + 0.5) * Float(size - 1)), Double((z / boardSize + 0.5) * Float(size - 1)))
    }

    /// Point normalisé de la carte ([0, 1]², origine en haut à gauche) → position 3D posée sur le relief.
    public func world(normalized p: SIMD2<Double>, on layout: AtlasLayout) -> SIMD3<Float> {
        let x = (Float(p.x) - 0.5) * boardSize
        let z = (Float(p.y) - 0.5) * boardSize
        let g = grid(x: x, z: z, size: layout.size)
        return SIMD3(x, layout.height.sample(g.x, g.y) * reliefHeight, z)
    }

    /// Lance un rayon et renvoie la première cellule du relief touchée, ou `nil` hors planche.
    /// On avance par petits pas jusqu'à passer sous la surface, puis on affine par dichotomie.
    public func hit(origin: SIMD3<Float>, direction: SIMD3<Float>, layout: AtlasLayout) -> SIMD2<Int>? {
        let dir = simd_normalize(direction)
        let half = boardSize / 2
        func below(_ t: Float) -> Bool? {
            let p = origin + dir * t
            guard abs(p.x) <= half, abs(p.z) <= half else { return nil }
            let g = grid(x: p.x, z: p.z, size: layout.size)
            return p.y <= layout.height.sample(g.x, g.y) * reliefHeight
        }
        let step = boardSize / Float(layout.size) / 2
        var previous: Float = 0
        var t: Float = 0
        let far = simd_length(origin) + boardSize * 2
        while t < far {
            if below(t) == true {
                // Dichotomie entre le dernier point au-dessus et le premier dessous.
                var low = previous, high = t
                for _ in 0..<12 {
                    let mid = (low + high) / 2
                    if below(mid) == true { high = mid } else { low = mid }
                }
                let p = origin + dir * high
                let g = grid(x: p.x, z: p.z, size: layout.size)
                let cell = SIMD2(Int(g.x.rounded()), Int(g.y.rounded()))
                return layout.height.contains(cell.x, cell.y) ? cell : nil
            }
            previous = t
            t += step
        }
        return nil
    }
}

extension AtlasLayout {
    /// Lieu sous une cellule, ou `nil` pour la mer.
    public func place(at cell: SIMD2<Int>) -> LaidPlace? {
        let index = place[cell.x, cell.y]
        return index < 0 ? nil : places[Int(index)]
    }
}
