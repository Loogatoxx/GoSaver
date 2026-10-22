import Foundation

/// Raster : grille carrée de valeurs, indexée (x, y), origine en haut à gauche.
/// (Le nom « Grid » est déjà pris par une vue SwiftUI.)
public struct Raster<Value: Sendable>: Sendable {
    public let size: Int
    public var values: [Value]

    public init(size: Int, repeating value: Value) {
        self.size = size
        values = Array(repeating: value, count: size * size)
    }

    @inlinable public subscript(x: Int, y: Int) -> Value {
        get { values[y * size + x] }
        set { values[y * size + x] = newValue }
    }

    @inlinable public func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < size && y < size
    }
}

extension Raster where Value == Float {
    /// Lissage par moyenne glissante (rayon 1), répété `passes` fois.
    public func smoothed(passes: Int = 1) -> Raster<Float> {
        var current = self
        for _ in 0..<passes {
            var next = current
            for y in 0..<size {
                for x in 0..<size {
                    var sum: Float = 0, count: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 where current.contains(x + dx, y + dy) {
                            sum += current[x + dx, y + dy]
                            count += 1
                        }
                    }
                    next[x, y] = sum / count
                }
            }
            current = next
        }
        return current
    }

    /// Valeur interpolée en un point continu (coordonnées de grille).
    public func sample(_ x: Double, _ y: Double) -> Float {
        let cx = min(max(x, 0), Double(size - 1)), cy = min(max(y, 0), Double(size - 1))
        let x0 = Int(cx), y0 = Int(cy)
        let x1 = min(x0 + 1, size - 1), y1 = min(y0 + 1, size - 1)
        let tx = Float(cx - Double(x0)), ty = Float(cy - Double(y0))
        let top = self[x0, y0] * (1 - tx) + self[x1, y0] * tx
        let bottom = self[x0, y1] * (1 - tx) + self[x1, y1] * tx
        return top * (1 - ty) + bottom * ty
    }
}

/// Distance (en cellules) de chaque cellule `true` à la plus proche cellule `false`.
/// Transformée de distance en deux passes (chanfrein 3-4, précision suffisante ici).
public func distanceField(inside mask: Raster<Bool>) -> Raster<Float> {
    let n = mask.size
    let far: Float = .greatestFiniteMagnitude / 4
    var d = Raster<Float>(size: n, repeating: 0)
    for i in d.values.indices { d.values[i] = mask.values[i] ? far : 0 }
    let straight: Float = 1, diagonal: Float = 1.4142
    for y in 0..<n {
        for x in 0..<n where d[x, y] > 0 {
            var best = d[x, y]
            if x > 0 { best = min(best, d[x - 1, y] + straight) }
            if y > 0 { best = min(best, d[x, y - 1] + straight) }
            if x > 0, y > 0 { best = min(best, d[x - 1, y - 1] + diagonal) }
            if x < n - 1, y > 0 { best = min(best, d[x + 1, y - 1] + diagonal) }
            d[x, y] = best
        }
    }
    for y in stride(from: n - 1, through: 0, by: -1) {
        for x in stride(from: n - 1, through: 0, by: -1) where d[x, y] > 0 {
            var best = d[x, y]
            if x < n - 1 { best = min(best, d[x + 1, y] + straight) }
            if y < n - 1 { best = min(best, d[x, y + 1] + straight) }
            if x < n - 1, y < n - 1 { best = min(best, d[x + 1, y + 1] + diagonal) }
            if x > 0, y < n - 1 { best = min(best, d[x - 1, y + 1] + diagonal) }
            d[x, y] = best
        }
    }
    // Une cellule « vraie » sans aucune cellule « fausse » reste à `far` : on la borne.
    for i in d.values.indices where d.values[i] >= far { d.values[i] = Float(n) }
    return d
}

/// Isolignes par « marching squares » : pour un niveau donné, renvoie les petits
/// segments où le champ franchit ce niveau. On les trace tels quels, sans les relier.
public func isoSegments(_ field: Raster<Float>, level: Float) -> [(SIMD2<Double>, SIMD2<Double>)] {
    var segments: [(SIMD2<Double>, SIMD2<Double>)] = []
    let n = field.size
    func lerpPoint(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) -> SIMD2<Double> {
        let a = field[ax, ay], b = field[bx, by]
        let t = a == b ? 0.5 : Double((level - a) / (b - a))
        return SIMD2(Double(ax) + t * Double(bx - ax), Double(ay) + t * Double(by - ay))
    }
    for y in 0..<(n - 1) {
        for x in 0..<(n - 1) {
            let tl = field[x, y] > level, tr = field[x + 1, y] > level
            let br = field[x + 1, y + 1] > level, bl = field[x, y + 1] > level
            let code = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0)
            if code == 0 || code == 15 { continue }
            let top = lerpPoint(x, y, x + 1, y), right = lerpPoint(x + 1, y, x + 1, y + 1)
            let bottom = lerpPoint(x, y + 1, x + 1, y + 1), left = lerpPoint(x, y, x, y + 1)
            switch code {
            case 1, 14: segments.append((left, bottom))
            case 2, 13: segments.append((bottom, right))
            case 3, 12: segments.append((left, right))
            case 4, 11: segments.append((top, right))
            case 6, 9: segments.append((top, bottom))
            case 7, 8: segments.append((left, top))
            case 5: segments.append((left, top)); segments.append((bottom, right))
            case 10: segments.append((top, right)); segments.append((left, bottom))
            default: break
            }
        }
    }
    return segments
}
